# CiviCRM on Drupal

A Docker image that runs [CiviCRM](https://civicrm.org) on top of the official [Drupal](https://hub.docker.com/_/drupal) image. CiviCRM and all Composer dependencies are installed at build time; the entrypoint only handles database initialization on first start.

## Quick start

```yaml
services:
  app:
    image: ghcr.io/your-org/civicrm-docker-drupal:latest
    ports:
      - "8080:80"
    environment:
      DRUPAL_DB_HOST: db
      DRUPAL_DB_NAME: drupal
      DRUPAL_DB_USER: drupal
      DRUPAL_DB_PASSWORD: pass
      CIVICRM_DB_HOST: db
      CIVICRM_DB_NAME: civicrm
      CIVICRM_DB_USER: drupal
      CIVICRM_DB_PASSWORD: pass
      DRUPAL_ADMIN_USER: admin
      DRUPAL_ADMIN_PASSWORD: admin
      DRUPAL_BASE_URL: http://localhost:8080
    volumes:
      - drupal-files:/opt/drupal/web/sites/default/files
      - drupal-private:/opt/drupal/private

  db:
    image: mariadb:10.11
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: drupal
      MYSQL_USER: drupal
      MYSQL_PASSWORD: pass
    volumes:
      - db:/var/lib/mysql

volumes:
  drupal-files:
  drupal-private:
  db:
```

See [example/compose-drupal.yaml](../../example/compose-drupal.yaml) for a complete example including automatic CiviCRM database creation.

## Environment variables

### Drupal database

| Variable | Default | Description |
|---|---|---|
| `DRUPAL_DB_HOST` | `db` | Database hostname |
| `DRUPAL_DB_PORT` | `3306` | Database port |
| `DRUPAL_DB_NAME` | `drupal` | Database name |
| `DRUPAL_DB_USER` | `drupal` | Database user |
| `DRUPAL_DB_PASSWORD` | `drupal` | Database password |

### CiviCRM database

CiviCRM can share the same database server but should use a separate database. All variables default to the Drupal DB connection if not set.

| Variable | Default | Description |
|---|---|---|
| `CIVICRM_DB_HOST` | `$DRUPAL_DB_HOST` | Database hostname |
| `CIVICRM_DB_PORT` | `$DRUPAL_DB_PORT` | Database port |
| `CIVICRM_DB_NAME` | `civicrm` | Database name |
| `CIVICRM_DB_USER` | `$DRUPAL_DB_USER` | Database user |
| `CIVICRM_DB_PASSWORD` | `$DRUPAL_DB_PASSWORD` | Database password |

### Drupal site

| Variable | Default | Description |
|---|---|---|
| `DRUPAL_ADMIN_USER` | `admin` | Admin account username |
| `DRUPAL_ADMIN_PASSWORD` | `admin` | Admin account password |
| `DRUPAL_ADMIN_EMAIL` | `admin@example.com` | Admin account email |
| `DRUPAL_SITE_NAME` | `CiviCRM` | Drupal site name |
| `DRUPAL_BASE_URL` | `http://localhost` | Public URL used by CiviCRM (must be reachable) |

### Behaviour

| Variable | Default | Description |
|---|---|---|
| `AUTO_INSTALL` | `true` | Run Drupal + CiviCRM install on first start |
| `AUTO_UPDATE` | `true` | Run `cv upgrade:db` on every start when already installed |
| `CIVICRM_EXTENSIONS` | _(empty)_ | Comma-separated list of CiviCRM extensions to install and enable on every start |

### Extensions

`CIVICRM_EXTENSIONS` accepts a comma-separated list of extension keys. On every container start, each extension is ensured to be installed and enabled — extensions are never disabled by removing them from the list.

```yaml
environment:
  CIVICRM_EXTENSIONS: "org.civicrm.volunteer, de.systopia.donrec"
```

For each extension the entrypoint first tries `cv dl <key>` to download it from the [CiviCRM Extension Directory](https://civicrm.org/extensions) and enable it. If the extension is already present in the filesystem (e.g. mounted as a volume), `cv en <key>` is used as a fallback.

## Volumes

| Path | Purpose |
|---|---|
| `/opt/drupal/web/sites/default/files` | Drupal public files |
| `/opt/drupal/web/sites/default/private` | Drupal private files (configure path in settings) |

## First start behaviour

1. Waits for the database to become available.
2. If `settings.php` does not exist: runs `drush site:install` then `cv core:install`.
3. If `settings.php` exists but the CiviCRM database tables are missing: re-runs `cv core:install`.
4. If fully installed and `AUTO_UPDATE=true`: runs `cv upgrade:db` and `cv ext:upgrade-db`.

## Build arguments

| ARG | Default | Description |
|---|---|---|
| `DRUPAL_VERSION` | `11` | Drupal major version (base image tag) |
| `CIVICRM_VERSION` | `6.10.1` | CiviCRM version installed via Composer |
