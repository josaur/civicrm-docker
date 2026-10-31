{{- define "civicrm-drupal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "civicrm-drupal.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "civicrm-drupal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "civicrm-drupal.labels" -}}
helm.sh/chart: {{ include "civicrm-drupal.chart" . }}
{{ include "civicrm-drupal.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "civicrm-drupal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "civicrm-drupal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "civicrm-drupal.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/* repository:tag, or repository:tag@sha256:... when image.digest is set (the digest wins). */}}
{{- define "civicrm-drupal.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s:%s@%s" .Values.image.repository (include "civicrm-drupal.imageTag" .) .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (include "civicrm-drupal.imageTag" .) }}
{{- end }}
{{- end }}

{{/* Tools image (init container, cron): repository:tag, or repository:tag@sha256:... when toolsImage.digest is set. */}}
{{- define "civicrm-drupal.toolsImage" -}}
{{- $tag := .Values.toolsImage.tag | default .Chart.AppVersion }}
{{- if .Values.toolsImage.digest }}
{{- printf "%s:%s@%s" .Values.toolsImage.repository $tag .Values.toolsImage.digest }}
{{- else }}
{{- printf "%s:%s" .Values.toolsImage.repository $tag }}
{{- end }}
{{- end }}

{{- define "civicrm-drupal.secretName" -}}
{{- required "app.existingSecret is required (the chart does not create secrets)" .Values.app.existingSecret }}
{{- end }}

{{/* Host header for the probes: Drupal rejects unknown hosts (trusted_host_patterns). */}}
{{- define "civicrm-drupal.probeHost" -}}
{{- first (required "app.trustedHosts needs at least one host" .Values.app.trustedHosts) }}
{{- end }}

{{/*
Environment shared by the app pod and the cron job. Secrets are not passed as environment variables:
the Secret is mounted as files and the image reads them from CIVI_MOUNT_DIR.
*/}}
{{- define "civicrm-drupal.env" -}}
- name: DRUPAL_DB_HOST
  value: {{ required "app.drupalDb.host is required" .Values.app.drupalDb.host | quote }}
- name: DRUPAL_DB_PORT
  value: {{ .Values.app.drupalDb.port | quote }}
- name: DRUPAL_DB_NAME
  value: {{ .Values.app.drupalDb.name | quote }}
- name: DRUPAL_DB_USER
  value: {{ .Values.app.drupalDb.user | quote }}
# Secrets are files in this directory (see the Secret volume), the image reads them by name
- name: CIVI_MOUNT_DIR
  value: /run/civi-secrets
- name: DRUPAL_TRUSTED_HOSTS
  value: {{ join "," (required "app.trustedHosts is required" .Values.app.trustedHosts) | quote }}
{{- if .Values.app.reverseProxyAddresses }}
- name: DRUPAL_REVERSE_PROXY_ADDRESSES
  value: {{ .Values.app.reverseProxyAddresses | quote }}
{{- end }}
- name: CIVICRM_BASE_URL
  value: {{ required "app.baseUrl is required" .Values.app.baseUrl | quote }}
{{- if .Values.app.deployId }}
- name: CIVICRM_DEPLOY_ID
  value: {{ .Values.app.deployId | quote }}
{{- end }}
{{- with .Values.app.civicrmDb }}
{{- if .host }}
- name: CIVICRM_DB_HOST
  value: {{ .host | quote }}
{{- end }}
{{- if .port }}
- name: CIVICRM_DB_PORT
  value: {{ .port | quote }}
{{- end }}
{{- if .name }}
- name: CIVICRM_DB_NAME
  value: {{ .name | quote }}
{{- end }}
{{- if .user }}
- name: CIVICRM_DB_USER
  value: {{ .user | quote }}
{{- end }}
{{- end }}
{{- with .Values.app.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "civicrm-drupal.secretMount" -}}
- name: secrets
  mountPath: /run/civi-secrets
  readOnly: true
{{- end }}

{{- define "civicrm-drupal.secretVolume" -}}
- name: secrets
  secret:
    secretName: {{ include "civicrm-drupal.secretName" . }}
    defaultMode: 0440
{{- end }}

{{/*
Extensions: the Helm values define which CiviCRM extensions exist. An init container downloads them into an
emptyDir that is mounted read-only into the application (never into the data volume: no PHP runs there).
*/}}
{{/* Init container (tools image): always present, it prepares /tmp and /data for the shell-less runtime image. */}}
{{- define "civicrm-drupal.initContainer" -}}
- name: prepare
  image: {{ include "civicrm-drupal.toolsImage" . | quote }}
  imagePullPolicy: {{ .Values.toolsImage.pullPolicy }}
  {{- if .Values.extensions }}
  command: ["sh", "/opt/tools/init.sh", "/config/extensions.list", "/ext"]
  {{- else }}
  command: ["sh", "/opt/tools/init.sh"]
  {{- end }}
  securityContext:
    {{- toYaml .Values.securityContext | nindent 4 }}
  resources:
    {{- toYaml .Values.init.resources | nindent 4 }}
  volumeMounts:
    - name: tmp
      mountPath: /tmp
    {{- if .Values.persistence.enabled }}
    - name: data
      mountPath: /data
    {{- end }}
    {{- if .Values.extensions }}
    - name: extensions
      mountPath: /ext
    - name: extensions-list
      mountPath: /config
      readOnly: true
    {{- end }}
{{- end }}

{{- define "civicrm-drupal.extensionsVolumes" -}}
- name: extensions
  emptyDir:
    sizeLimit: {{ .Values.init.extensionsSizeLimit }}
- name: extensions-list
  configMap:
    name: {{ include "civicrm-drupal.fullname" . }}-extensions
    defaultMode: 0444
{{- end }}

{{- define "civicrm-drupal.extensionsMount" -}}
- name: extensions
  mountPath: /opt/drupal/web/sites/default/ext
  readOnly: true
{{- end }}
