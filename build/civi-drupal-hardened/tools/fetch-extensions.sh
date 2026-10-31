#!/bin/sh
# Downloads CiviCRM extensions into an (initially empty) directory. Meant for an init container:
# unprivileged user, read-only root filesystem, only /tmp and the target directory are writable.
#
# The target directory is later mounted read-only at web/sites/default/ext (see civicrm.settings.php).
# Nothing is installed at runtime and nothing is written into the data volume (PHP does not run there).
#
# Usage:  sh /opt/tools/fetch-extensions.sh <list-file> [target-dir]
#   list-file    one extension per line: "<key> <https-url-of-zip> <sha256-of-zip>"
#   target-dir   default /ext
#
# Every archive is verified against its SHA-256. The key must match the key in the info.xml.
# Any error aborts with a non-zero exit code, so the pod does not start with a partial set.
set -eu
umask 022

list="${1:?usage: fetch-extensions.sh <list-file> [target-dir]}"
target="${2:-/ext}"
n=0

while read -r ext url sha; do
  [ -n "$ext" ] || continue
  case "$ext" in
    *[!A-Za-z0-9._-]*) echo "ERROR: invalid extension name: $ext" >&2; exit 1 ;;
  esac
  case "$url" in
    https://*) ;;
    *) echo "ERROR: $ext: the URL must start with https://" >&2; exit 1 ;;
  esac

  echo "Extension $ext"
  zip="/tmp/$ext.zip"
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 300 -o "$zip" "$url"
  echo "$sha  $zip" | sha256sum -c -

  work=$(mktemp -d /tmp/ext.XXXXXX)
  unzip -q "$zip" -d "$work"
  info=$(find "$work" -maxdepth 2 -name info.xml | head -n 1)
  [ -n "$info" ] || { echo "ERROR: $ext: no info.xml in the archive" >&2; exit 1; }
  grep -q "<extension key=\"$ext\"" "$info" || { echo "ERROR: $ext: name does not match info.xml" >&2; exit 1; }
  [ ! -e "$target/$ext" ] || { echo "ERROR: $ext is listed twice" >&2; exit 1; }
  mv "$(dirname "$info")" "$target/$ext"
  n=$((n + 1))
done < "$list"

echo "$n extension(s) installed in $target"
