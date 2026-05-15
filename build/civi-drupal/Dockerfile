ARG DRUPAL_VERSION=11
ARG CIVICRM_VERSION=6.10.1

# --- Stage 1: Composer build ---
# Installs PHP extensions needed by CiviCRM so Composer can resolve them,
# then pulls in all CiviCRM packages. Only the resulting /opt/drupal tree
# is copied forward — no build tools end up in the runtime image.

FROM drupal:${DRUPAL_VERSION} AS build

ARG CIVICRM_VERSION=6.10.1

RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libicu-dev \
        libpng-dev \
        libzip-dev \
        unzip \
    && \
    docker-php-ext-install bcmath intl mysqli zip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/drupal

# civicrm/composer-compile-plugin needs this to skip interactive prompts
ENV COMPOSER_COMPILE=all

RUN set -eux; \
    # Allow all plugins — required for civicrm-asset-plugin and other CiviCRM plugins
    composer config --no-interaction allow-plugins true && \
    # CiviCRM pins firebase/php-jwt <7 which has a known advisory (PKSA-y2cr-5h3j-g3ys);
    # the pin is intentional upstream. Disable block-insecure so Composer doesn't abort.
    composer config --no-interaction audit.ignore '["PKSA-y2cr-5h3j-g3ys"]' && \
    composer config --no-interaction --json audit.abandoned ignore ; \
    composer config --no-interaction audit.block-insecure false && \
    composer require --no-interaction --no-progress \
        civicrm/cli-tools \
        civicrm/civicrm-core:${CIVICRM_VERSION} \
        civicrm/civicrm-packages:${CIVICRM_VERSION} \
        civicrm/civicrm-drupal-8:${CIVICRM_VERSION} \
        drush/drush \
        "brick/money:>=0.5.0,<0.6.0" && \
    composer install --no-interaction --optimize-autoloader



# --- Stage 2: Runtime image ---

FROM drupal:${DRUPAL_VERSION}

RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        cron \
        libicu-dev \
        libpng-dev \
        libzip-dev \
        unzip \
    && \
    docker-php-ext-install bcmath intl mysqli zip && \
    rm -rf /var/lib/apt/lists/*

# Download cv CLI
RUN curl -LsS https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
    && chmod +x /usr/local/bin/cv

# Enable Apache modules
RUN a2enmod rewrite remoteip

# Replace default vhost — Drupal's document root is /opt/drupal/web
COPY apache-default.conf /etc/apache2/sites-available/000-default.conf

# Copy fully-built application from build stage
COPY --from=build --chown=www-data:www-data /opt/drupal /opt/drupal

COPY civi-drupal-entrypoint /usr/local/bin/
RUN chmod +x /usr/local/bin/civi-drupal-entrypoint

# CiviCRM needs more memory than the PHP default (128M) during install and runtime
RUN echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/civicrm-memory.ini

ENV CIVICRM_UF=Drupal8

ENTRYPOINT ["civi-drupal-entrypoint"]
CMD ["apache2-foreground"]
