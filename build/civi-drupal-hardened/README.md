# CiviCRM on Drupal (hardened)

A hardened variant of [`build/civi-drupal`](../civi-drupal): **Drupal 11 + CiviCRM on PHP 8.5**, built to run

- **immutable**: application code is owned by root and not writable, no package manager in the image,
- **read-only**: the root filesystem can be mounted read-only; only `/tmp` (tmpfs) and `/data` (volume) are writable,
- **non-root**: runs as an unprivileged user (default UID 33, any other UID works, for example 10033 in the Helm chart), Apache listens on port **8080**, all capabilities can be dropped,
- **without secrets in the image**: every setting comes from environment variables or from mounted files; missing required values abort the start,
- **extensions from outside**: CiviCRM extensions are mounted read-only at `web/sites/default/ext` (see [Extensions](#extensions)).

A Helm chart is in [`helm/civicrm-drupal`](../../helm/civicrm-drupal).

## Differences to `build/civi-drupal`

| | `civi-drupal` | `civi-drupal-hardened` |
|---|---|---|
| User | root entrypoint | unprivileged user only (default UID 33) |
| Root filesystem | writable | read-only capable |
| Code | writable | root-owned, `a-w`, no Composer/apt at runtime |
| Config | generated on first start | env-driven `settings.php` / `civicrm.settings.php` |
| PHP in uploads | not restricted | no PHP execution below `sites/*/files` and `/data` |
| Web PHP | default | `disable_functions` (exec, shell_exec, system, proc_open, popen, ...), `open_basedir` |
| Port | 80 | 8080 |

## Build

```sh
docker build -t civi-drupal-hardened build/civi-drupal-hardened
# optional build args
docker build --build-arg DRUPAL_VERSION=11.4.11 --build-arg CIVICRM_VERSION=6.19.2 ...
```

The base image tag (`drupal:11.4.11-php8.5-apache-trixie`) can lag behind the latest Drupal release; the Dockerfile raises core to `DRUPAL_VERSION` with Composer.

## Run

```sh
docker run -d --name civi \
  --read-only --user 10033:10033 --cap-drop=ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=512m \
  -v civi-data:/data:U \
  --env-file civi.env \
  -p 8080:8080 civi-drupal-hardened
```

### Environment variables

Secrets (marked *secret* below) can also be provided as files instead of environment variables: set
`CIVI_MOUNT_DIR` to a directory (for example a mounted Kubernetes Secret) that contains one file per secret, named
like the variable in lower case with dashes (`DRUPAL_DB_PASSWORD` -> `drupal-db-password`). An environment variable
wins over a file. Files keep secrets out of the container environment.

| Variable | Required | Description |
|---|---|---|
| `DRUPAL_DB_HOST`, `DRUPAL_DB_PORT`, `DRUPAL_DB_NAME`, `DRUPAL_DB_USER`, `DRUPAL_DB_PASSWORD` *(secret)* | yes | Drupal database (CiviCRM uses the same database unless overridden below) |
| `DRUPAL_HASH_SALT` *(secret)* | **yes** | e.g. `openssl rand -hex 32` |
| `DRUPAL_TRUSTED_HOSTS` | recommended | comma separated host names, default `localhost,127.0.0.1` |
| `DRUPAL_REVERSE_PROXY_ADDRESSES` | when behind a proxy | comma separated proxy IPs/CIDRs |
| `CIVICRM_BASE_URL` | **yes** | public base URL, e.g. `https://civi.example.org` |
| `CIVICRM_SITE_KEY` *(secret)* | **yes** | e.g. `openssl rand -hex 16` |
| `CIVICRM_CRED_KEYS` *(secret)* | **yes** | `aes-cbc:hkdf-sha256:<openssl rand -base64 32>`. **Back this up**: stored credentials are encrypted with it |
| `CIVICRM_SIGN_KEYS` *(secret)* | **yes** | `jwt-hs256:hkdf-sha256:<openssl rand -base64 32>` |
| `CIVICRM_DEPLOY_ID` | no | |
| `CIVICRM_DB_HOST` / `_PORT` / `_NAME` / `_USER` / `_PASSWORD` *(secret)* | no | use a separate CiviCRM database |
| `CIVI_MOUNT_DIR` | no | directory with secret files, see above |
| `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` *(secret)* | no | credentials of the OpenID Connect client (see below) |

### Kubernetes

```yaml
securityContext:            # pod
  runAsNonRoot: true
  runAsUser: 10033
  runAsGroup: 10033
  fsGroup: 10033
  seccompProfile: { type: RuntimeDefault }
containers:
  - securityContext:        # container
      runAsNonRoot: true
      privileged: false
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities: { drop: ["ALL"] }
      seccompProfile: { type: RuntimeDefault }
    volumeMounts:
      - { name: tmp,  mountPath: /tmp }     # emptyDir (medium: Memory is fine)
      - { name: data, mountPath: /data }    # PersistentVolumeClaim
```

The Helm chart in [`helm/civicrm-drupal`](../../helm/civicrm-drupal) sets all of this, mounts the Secret as files, adds a NetworkPolicy and an optional CronJob.

## First installation

All commands run in the hardened container (same flags as above, one-off, e.g. a Job):

```sh
# 1. Install Drupal into an empty database
drush site:install standard -y --account-name=admin --account-pass="$ADMIN_PASS" --site-name=Civi --locale=de

# 2. Make CiviCRM full-width and reachable from the front page
sh /opt/tools/configure-drupal.sh
```

`configure-drupal.sh` enables `civicrmtheme` and serves CiviCRM pages in Claro (the front-end theme Olivero limits the content to a narrow column) and adds a main menu entry "CiviCRM".

For a brand-new CiviCRM instead of a migration, enable the module and install CiviCRM as described in the upstream docs.

## Importing an existing CiviCRM database

The image contains `cv`, `drush` and the MariaDB client, so an existing CiviCRM database can be imported and upgraded from inside the hardened container (`cv upgrade:db`). Keep in mind when importing:

- **Re-enter credentials** (SMTP, payment processors, API keys) and rotate them if the source system was compromised.
- **Create Drupal users.** The mapping to CiviCRM contacts is rebuilt on first login (by e-mail).
- **Remove registrations of extensions that are not available.** `cv upgrade:db` stops with `Invalid extension key` if the database lists an extension that is not in the image or in the extensions directory. Delete its row from `civicrm_extension` (the data tables stay), or provide the extension as described in [Extensions](#extensions), and run the upgrade again.
- Set up cron: `cv api job.execute` (for example as a Kubernetes CronJob using this image).

## OpenID Connect login

The image contains the Drupal module `openid_connect` (generic client, callback `/openid-connect/generic`). It is not enabled by
default. To use an identity provider, enable it and store the endpoints as configuration (`openid_connect.settings.generic`); the
client credentials are read from `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` (environment or files in `CIVI_MOUNT_DIR`) and override the
stored values in `settings.php`, so they never end up in the database or in exported configuration. Typical settings:
`connect_existing_users: true` (match by e-mail) and `override_registration_settings: false` (unknown people do not get an account).

## Extensions

The extensions directory is `web/sites/default/ext` (`extensionsDir`/`extensionsURL` are set in `civicrm.settings.php`).
It is empty in the image and **not** below `/data`, because PHP does not run there. A deployment mounts the extensions
there read-only. Nothing is installed at runtime and the volume stays free of code.

`/opt/tools/fetch-extensions.sh <list-file> [target-dir]` is made for an init container: it downloads every zip over
https, verifies its SHA-256, checks that the name matches the `info.xml` and moves it to `<target-dir>/<key>`. Any error
aborts with a non-zero exit code. The list has one line per extension: `<key> <https-url> <sha256>`. The Helm chart
defines the list in its values and mounts the result read-only. Enable an extension once with `cv ext:enable <key>`.

## Tests

Verified locally with `podman` and with a `kind` cluster (rootless, the chart from `helm/civicrm-drupal` as a StatefulSet):

- Drupal install, import of an existing CiviCRM 6.12.2 database and the upgrade to 6.19.2 (`cv upgrade:db`) in a pod with `readOnlyRootFilesystem`, UID 10033, `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false` and seccomp `RuntimeDefault`. Record counts of contacts, contributions, participants and activities are identical before and after the upgrade.
- Login, CiviCRM dashboard, contact search and the pages of an installed extension return 200.
- Process check in the running pod: effective, permitted, bounding, inheritable and ambient capabilities are all empty, `NoNewPrivs: 1`, seccomp active, no service account token, no secrets in the environment (they are files).
- Hardening: `settings.php`, `civicrm.settings.php`, `composer.json`, `update.php` and PHP files in the extensions directory return 403; a `.php` or `.phtml` file placed in the files directory is not executed or served; writing into the code tree, the extensions directory and the secrets directory fails; no version in `Server`/`X-Generator` headers.
- Extensions: two real extensions from different sources were downloaded by the init container, verified, mounted read-only and enabled. A wrong SHA-256, a name that does not match `info.xml`, a duplicate and a failing download each abort the init container (non-zero exit), so the pod does not start.
- CronJob (init container, volume on the node of the application pod, `drush cron`, `cv api job.execute`) completes.
- NetworkPolicy is enforced (egress to a port that is not allowed times out, database and HTTP work).

Not verified: `docker build` with Docker/BuildKit (the image was built with `podman build`; CI builds it with BuildKit), the `kubescape` scan, and a cluster with a different CNI or storage class.

## Notes

- `open_basedir` and `disable_functions` apply to **web** requests only. `cv` and `drush` need `proc_open` and run from the CLI.
- PHP 8.5 with CiviCRM 6.19 worked in the tests above; check upstream support before upgrading either.
- Do not commit dumps. They contain personal data.
