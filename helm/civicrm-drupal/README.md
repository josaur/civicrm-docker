# civicrm-drupal Helm chart

CiviCRM on Drupal 11 for the image built from [`build/civi-drupal-hardened`](../../build/civi-drupal-hardened):
immutable, read-only root filesystem, unprivileged user, no capabilities. The chart expects an **external
MariaDB** and an **existing Secret**. It never creates secrets and has no database sub-chart.

## What the chart sets

| Area | Setting |
|---|---|
| Pod | `runAsNonRoot`, UID/GID/`fsGroup` 10033, seccomp `RuntimeDefault`, no service account token, no service links |
| Container | `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `privileged: false`, `capabilities.drop: [ALL]` |
| Writable | `/tmp` (in-memory `emptyDir`) and `/data` (PVC). Everything else is read-only |
| Secrets | the Secret is mounted read-only as files at `/run/civi-secrets`, not as environment variables |
| Network | `NetworkPolicy` (default deny, DNS, database, HTTPS, SMTP), restrict the sources with `networkPolicy.ingressFrom` |
| Resources | requests and limits (CPU and memory) for every container, including init and cron |
| Image | pin with `image.digest`, pull policy `Always` |
| Extensions | defined in the values, fetched by an init container, mounted read-only |

## Install

1. Create the database (utf8mb4) and a user, and a Secret with these keys (files in `/run/civi-secrets`):

   | Key | Content |
   |---|---|
   | `drupal-db-password` | password of `app.drupalDb.user` |
   | `drupal-hash-salt` | `openssl rand -hex 32` |
   | `civicrm-site-key` | `openssl rand -hex 16` |
   | `civicrm-cred-keys` | `aes-cbc:hkdf-sha256:` + `openssl rand -base64 32`. **Back it up**: stored credentials are encrypted with it |
   | `civicrm-sign-keys` | `jwt-hs256:hkdf-sha256:` + `openssl rand -base64 32` |
   | `civicrm-db-password` | optional, only with `app.civicrmDb` |

2. Install with the required values:

   ```sh
   helm install civicrm ./helm/civicrm-drupal -n <namespace> \
     --set app.existingSecret=<secret> \
     --set app.drupalDb.host=<db-host> \
     --set app.baseUrl=https://civi.example.org \
     --set 'app.trustedHosts={civi.example.org}'
   ```

3. First start of an empty database: run `drush site:install` and `sh /opt/tools/configure-drupal.sh` once in a pod
   with the same security settings (see the image README). To migrate an existing CiviCRM database, import it
   first, enable the `civicrm` module, delete the registrations of unavailable extensions and run `cv upgrade:db`.
   Run the commands through `/usr/local/bin/civi-entrypoint.sh <command>` in a one-off pod, so the data directories exist.

## Extensions

```yaml
extensions:
  - key: org.example.myextension
    url: https://example.com/releases/org.example.myextension-1.0.0.zip
    sha256: "<sha256 of the zip>"
```

An init container (same image, same security context) runs `/opt/tools/fetch-extensions.sh`: https only, SHA-256
verified, name checked against `info.xml`, any error stops the pod from starting. The files are mounted read-only
at `web/sites/default/ext`. This is deliberately **not** below `/data`, where PHP does not run. Enable an extension
once with `cv ext:enable <key>`. The CronJob gets the same extensions.

## CronJob

`cronjob.enabled=true` runs `drush cron` and `cv api job.execute` on a schedule. The job runs on the node of the
application pod (`cronjob.coLocate`), because the volume is `ReadWriteOnce`. It executes **all active CiviCRM
jobs**, including mailing jobs. Configure the outbound mail first, then enable it.

## Linting

The rendered chart passes `kube-linter`, `kubeconform` (strict), `checkov` and, apart from the registry allow list
(`KSV-0125`, a policy of the target cluster), `trivy config`. `polaris` only reports the label convention of Helm,
the missing priority class and, for a single replica, the topology spread constraint.

```sh
helm template civi ./helm/civicrm-drupal -n civi -f my-values.yaml > /tmp/render.yaml
kube-linter lint /tmp/render.yaml
```
