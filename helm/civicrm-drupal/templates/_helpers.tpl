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

{{/*
MariaDB host: Bitnami sub-chart service when enabled, else explicit host.
Bitnami names the primary service "<release>-mariadb".
*/}}
{{- define "civicrm-drupal.dbHost" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s-mariadb" .Release.Name }}
{{- else }}
{{- required "app.drupalDb.host is required when mariadb.enabled=false" .Values.app.drupalDb.host }}
{{- end }}
{{- end }}

{{- define "civicrm-drupal.civicrmDbHost" -}}
{{- if .Values.app.civicrmDb.host }}
{{- .Values.app.civicrmDb.host }}
{{- else }}
{{- include "civicrm-drupal.dbHost" . }}
{{- end }}
{{- end }}

{{- define "civicrm-drupal.civicrmDbUser" -}}
{{- .Values.app.civicrmDb.user | default .Values.app.drupalDb.user }}
{{- end }}

{{- define "civicrm-drupal.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}
