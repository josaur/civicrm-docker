#!/bin/sh
# Entrypoint for the read-only image. Runs as www-data (UID 33), never as root.
set -eu

# Only /tmp (tmpfs) and /data (volume) are writable.
mkdir -p /tmp/apache2/lock /tmp/civicrm/templates_c /tmp/drupal-php

# Create the persistent directories in the volume if it is empty
for d in /data/public /data/public/civicrm /data/private /data/private/config /data/private/civicrm; do
  [ -d "$d" ] || mkdir -p "$d"
done

export APACHE_PID_FILE=/tmp/apache2/apache2.pid
export APACHE_RUN_DIR=/tmp/apache2
export APACHE_LOCK_DIR=/tmp/apache2/lock

exec "$@"
