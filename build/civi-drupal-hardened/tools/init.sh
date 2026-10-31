#!/bin/sh
# Init container for the distroless runtime image (the runtime image has no shell, so everything that needs one happens here).
# Runs with the same unprivileged user, read-only root filesystem and volumes as the application:
#   1. creates the writable directories in /tmp (tmpfs) and /data (volume)
#   2. if a list of extensions is given, installs them into the target directory (see fetch-extensions.sh)
#
# Usage:  sh /opt/tools/init.sh [<extensions-list-file> [<target-dir>]]
set -eu

mkdir -p /tmp/civicrm/templates_c /tmp/drupal-php
for d in /data/public /data/public/civicrm /data/private /data/private/config /data/private/civicrm; do
  [ -d "$d" ] || mkdir -p "$d"
done

if [ -n "${1:-}" ] && [ -s "$1" ]; then
  exec sh /opt/tools/fetch-extensions.sh "$1" "${2:-/ext}"
fi
echo "init: directories ready, no extensions requested"
