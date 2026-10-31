# CiviCRM on Drupal 11 / PHP 8.5 - immutable, read-only capable, non-root.
#
# Multi-stage, two images in different privilege levels (build one with --target):
#   runtime  distroless: Apache + mod_php + the application, no shell, no package manager, no curl/unzip/mysql, no Composer.
#            This is the long-running container.
#   tools    php-apache with a shell, curl, unzip, mariadb-client, php CLI, cv and drush, no Composer, no compilers. For the init
#            container (directories, extension download), the CronJob and one-off jobs (install, upgrade). Never serves traffic.
# Composer, compilers and -dev packages exist only in the build stage.
#
# Runtime (only /tmp and /data are writable, a tools init container prepares them):
#   docker run --read-only --user 33:33 --cap-drop=ALL \
#     --security-opt no-new-privileges \
#     --tmpfs /tmp -v civi-data:/data -p 8080:8080 --env-file civi.env <image>
#
# See README.md for the required environment variables.

# PHP_IMAGE must have the same PHP version as DRUPAL_IMAGE (extensions are compiled in the build stage; checked below).
ARG PHP_IMAGE=php:8.5.12-apache-trixie
ARG DRUPAL_IMAGE=drupal:11.4.11-php8.5-apache-trixie
ARG DISTROLESS_IMAGE=gcr.io/distroless/base-debian13:nonroot

# ---------------------------------------------------------------------------------------------------------------------
# Stage 1: build
# ---------------------------------------------------------------------------------------------------------------------
FROM ${DRUPAL_IMAGE} AS build

# Raise Drupal core / pin CiviCRM. The base image tag may lag behind the latest core release.
ARG DRUPAL_VERSION=11.4.11
ARG CIVICRM_VERSION=6.19.2

USER root

# PHP extensions CiviCRM needs on top of the Drupal image
RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu-dev libzip-dev unzip \
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
      "drupal/openid_connect:^1.6" \
 && composer clear-cache

# cv (CiviCRM CLI) for upgrades and operations
RUN curl -fsSL https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
 && chmod 0755 /usr/local/bin/cv

# Prepare the tree: public files live in the volume (web/sites/default/files is only a symlink to it), the extensions directory
# stays empty and read-only (see civicrm.settings.php), code is owned by root and not writable.
RUN rm -rf web/sites/default/files \
 && ln -s /data/public web/sites/default/files \
 && rm -f web/sites/default/default.settings.php web/sites/default/default.services.yml \
 && mkdir -p web/sites/default/ext \
 && chown -R root:root /opt/drupal \
 && chmod -R a-w /opt/drupal \
 && find /opt/drupal -type d -exec chmod a+rx {} +

# Shared libraries the compiled PHP extensions need at runtime (same approach as the official Drupal image)
RUN set -eux; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
      | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
      | sort -u \
      | xargs -r dpkg-query --search \
      | cut -d: -f1 | sort -u > /runtime-packages.txt; \
    php -r 'echo PHP_VERSION;' > /php-version; \
    test -s /runtime-packages.txt

# ---------------------------------------------------------------------------------------------------------------------
# Stage 2: tools (shell and tools for init container, jobs and cron; no Composer, no compilers, no -dev packages)
# ---------------------------------------------------------------------------------------------------------------------
FROM ${PHP_IMAGE} AS tools

USER root

# Runtime libraries of the extensions, MariaDB client (drush sql, import) and unzip (extension init container)
COPY --from=build /runtime-packages.txt /php-version /tmp/
RUN set -eux; \
    test "$(php -r 'echo PHP_VERSION;')" = "$(cat /tmp/php-version)" || { echo "PHP version of PHP_IMAGE and DRUPAL_IMAGE differ" >&2; exit 1; }; \
    apt-get update; \
    apt-get install -y --no-install-recommends $(cat /tmp/runtime-packages.txt) mariadb-client unzip; \
    rm -rf /var/lib/apt/lists/* /tmp/runtime-packages.txt /tmp/php-version

# Compiled extensions and their ini files (gd, pdo_mysql, pdo_pgsql, zip, intl, bcmath, mysqli, recommended Drupal/opcache settings)
COPY --from=build /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=build /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Application: Drupal + CiviCRM + drush, cv. /var/www/html is the Apache document root of the php image.
COPY --from=build /opt/drupal /opt/drupal
COPY --from=build /usr/local/bin/cv /usr/local/bin/cv
RUN rmdir /var/www/html && ln -s /opt/drupal/web /var/www/html

# Hardened, environment-driven configuration (no secrets in the image)
COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/civi-entrypoint.sh \
 && chmod a-w /opt/drupal/web/sites/default/settings.php /opt/drupal/web/sites/default/civicrm.settings.php \
 # Apache as non-root: port 8080
 && sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/*.conf \
 && a2enmod expires rewrite headers >/dev/null \
 && a2enconf zz-civi-hardening \
 && (a2dismod -f status autoindex >/dev/null 2>&1 || true)

# One-off helper scripts: Drupal configuration for CiviCRM (theme, menu), extension download for the init container
COPY tools/ /opt/tools/
RUN chmod 0755 /opt/tools/*.sh && chmod -R a-w /opt/tools

# The php image ships compilers and PHP build tools (PHPIZE_DEPS, libc headers, phpize, pecl, the PHP source). Nothing is built at
# runtime: remove them, then make sure no shared library the runtime needs was removed with them. No package manager at runtime.
RUN set -eux; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS libc6-dev; \
    rm -rf /usr/src/php* /usr/local/include /usr/local/lib/php/build /usr/local/lib/php/doc /usr/local/lib/php/test \
      /usr/local/bin/phpize /usr/local/bin/php-config /usr/local/bin/pear /usr/local/bin/peardev /usr/local/bin/pecl \
      /usr/local/bin/docker-php-ext-* /usr/local/bin/docker-php-source /var/lib/apt/lists/*; \
    for f in /usr/local/bin/php /usr/sbin/apache2 /usr/local/lib/php/extensions/*/*.so /usr/lib/apache2/modules/*.so; do \
      if ldd "$f" 2>&1 | grep 'not found'; then echo "missing shared library for $f after cleanup" >&2; exit 1; fi; \
    done; \
    php -r 'foreach (["intl","gd","pdo_mysql","mysqli","zip","bcmath"] as $e) { if (!extension_loaded($e)) { fwrite(STDERR, "missing extension $e\n"); exit(1); } }'; \
    mkdir -p /data; chown 33:33 /data; \
    rm -f /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg

# HOME in tmpfs: cv/drush keep working data there (root filesystem is read-only)
ENV HOME=/tmp \
    PATH="/opt/drupal/vendor/bin:${PATH}" \
    APACHE_PID_FILE=/tmp/apache2/apache2.pid \
    APACHE_RUN_DIR=/tmp/apache2 \
    APACHE_LOCK_DIR=/tmp/apache2/lock

WORKDIR /opt/drupal
EXPOSE 8080
VOLUME ["/data"]
USER 33:33
ENTRYPOINT ["/usr/local/bin/civi-entrypoint.sh"]
CMD ["apache2-foreground"]

# ---------------------------------------------------------------------------------------------------------------------
# Stage 3: collect what the distroless runtime needs (Apache, mod_php, extensions, shared libraries)
# ---------------------------------------------------------------------------------------------------------------------
FROM ${DISTROLESS_IMAGE} AS distro

FROM tools AS closure
USER root
COPY --from=distro / /distro
COPY build-scripts/closure.sh /closure.sh
RUN sh /closure.sh

# ---------------------------------------------------------------------------------------------------------------------
# Stage 4: runtime (distroless: no shell, no package manager)
# ---------------------------------------------------------------------------------------------------------------------
FROM ${DISTROLESS_IMAGE} AS runtime

COPY --from=closure /rootfs/ /
COPY --from=build /opt/drupal /opt/drupal
COPY --chmod=0444 rootfs/opt/drupal/web/sites/default/settings.php /opt/drupal/web/sites/default/settings.php
COPY --chmod=0444 rootfs/opt/drupal/web/sites/default/civicrm.settings.php /opt/drupal/web/sites/default/civicrm.settings.php
COPY --chmod=0444 rootfs/usr/local/etc/php/conf.d/zz-civi.ini /usr/local/etc/php/conf.d/zz-civi.ini
COPY --chmod=0444 runtime/etc/apache2-civi/httpd.conf /etc/apache2-civi/httpd.conf
COPY --chmod=0444 rootfs/etc/apache2/conf-available/zz-civi-hardening.conf /etc/apache2-civi/conf/zz-civi-hardening.conf

STOPSIGNAL SIGWINCH
WORKDIR /opt/drupal
EXPOSE 8080
VOLUME ["/data"]
USER 10033:10033
ENTRYPOINT ["/usr/sbin/apache2", "-f", "/etc/apache2-civi/httpd.conf", "-D", "FOREGROUND"]
