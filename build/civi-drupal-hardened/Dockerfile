# CiviCRM on Drupal 11 / PHP 8.5 - immutable, read-only capable, non-root.
#
# Runtime (only /tmp and /data are writable):
#   docker run --read-only --user 33:33 --cap-drop=ALL \
#     --security-opt no-new-privileges \
#     --tmpfs /tmp -v civi-data:/data -p 8080:8080 --env-file civi.env <image>
#
# See README.md for the required environment variables.
ARG DRUPAL_IMAGE=drupal:11.4.11-php8.5-apache-trixie
FROM ${DRUPAL_IMAGE}

# Raise Drupal core / pin CiviCRM. The base image tag may lag behind the latest core release.
ARG DRUPAL_VERSION=11.4.11
ARG CIVICRM_VERSION=6.19.2

USER root

# PHP extensions CiviCRM needs on top of the Drupal image
RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu-dev libzip-dev unzip mariadb-client \
 && docker-php-ext-install -j"$(nproc)" intl bcmath mysqli \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/drupal
ENV COMPOSER_ALLOW_SUPERUSER=1

# Move Drupal core to the requested version
RUN composer require --no-interaction --update-with-dependencies \
      "drupal/core-recommended:${DRUPAL_VERSION}" \
      "drupal/core-composer-scaffold:${DRUPAL_VERSION}" \
      "drupal/core-project-message:${DRUPAL_VERSION}"

# CiviCRM via Composer, as documented for Drupal
RUN composer config --no-plugins allow-plugins.civicrm/composer-compile-plugin true \
 && composer config --no-plugins allow-plugins.civicrm/composer-downloads-plugin true \
 && composer config --no-plugins allow-plugins.civicrm/civicrm-asset-plugin true \
 && composer config --no-plugins allow-plugins.cweagans/composer-patches true \
 && composer config extra.enable-patching true \
 && composer config extra.compile-mode all \
 && composer require --no-interaction --update-with-dependencies \
      "civicrm/civicrm-asset-plugin" \
      "civicrm/civicrm-core:${CIVICRM_VERSION}" \
      "civicrm/civicrm-packages:${CIVICRM_VERSION}" \
      "civicrm/civicrm-drupal-8:${CIVICRM_VERSION}" \
      "drush/drush" \
 && composer clear-cache

# cv (CiviCRM CLI) for upgrades and operations
RUN curl -fsSL https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
 && chmod 0755 /usr/local/bin/cv

# Hardened, environment-driven configuration (no secrets in the image)
COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/civi-entrypoint.sh \
 # Apache as non-root: port 8080
 && sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/*.conf \
 && a2enmod headers >/dev/null \
 && a2enconf zz-civi-hardening \
 && (a2dismod -f status autoindex >/dev/null 2>&1 || true)

# One-off helper script: Drupal configuration for CiviCRM (theme, menu)
COPY tools/ /opt/tools/
RUN chmod 0755 /opt/tools/*.sh && chmod -R a-w /opt/tools

# Public files live in the volume; web/sites/default/files is only a symlink to it
RUN rm -rf /opt/drupal/web/sites/default/files \
 && ln -s /data/public /opt/drupal/web/sites/default/files \
 && rm -f /opt/drupal/web/sites/default/default.settings.php /opt/drupal/web/sites/default/default.services.yml \
 && mkdir -p /data && chown 33:33 /data

# Mount point for CiviCRM extensions (see civicrm.settings.php); stays empty and read-only in the image
RUN mkdir -p /opt/drupal/web/sites/default/ext

# Make it immutable: code is owned by root and not writable by www-data.
# Remove package managers so nothing can be installed at runtime.
RUN chown -R root:root /opt/drupal \
 && chmod -R a-w /opt/drupal \
 && find /opt/drupal -type d -exec chmod a+rx {} + \
 && rm -f /usr/local/bin/composer /usr/bin/composer \
 && rm -f /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg 2>/dev/null || true

# HOME in tmpfs: cv/drush keep working data there (root filesystem is read-only)
ENV HOME=/tmp \
    PATH="/opt/drupal/vendor/bin:${PATH}" \
    APACHE_PID_FILE=/tmp/apache2/apache2.pid \
    APACHE_RUN_DIR=/tmp/apache2 \
    APACHE_LOCK_DIR=/tmp/apache2/lock

EXPOSE 8080
VOLUME ["/data"]
USER 33:33
ENTRYPOINT ["/usr/local/bin/civi-entrypoint.sh"]
CMD ["apache2-foreground"]
