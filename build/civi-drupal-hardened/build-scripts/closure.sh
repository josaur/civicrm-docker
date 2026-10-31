#!/bin/sh
# Collects everything the distroless runtime image needs from the php-apache based stage into /rootfs:
# the Apache binary and the modules we load, mod_php, the PHP extensions with their ini files, and every shared library
# they need (ldd closure). Libraries the distroless base already ships (glibc, OpenSSL, ...) are not copied: its versions stay.
set -eu
DISTRO=/distro
OUT=/rootfs
MODULES="mpm_prefork authn_core authz_core authz_host access_compat alias dir env expires filter deflate headers mime reqtimeout rewrite setenvif"

mkdir -p "$OUT/usr/sbin" "$OUT/usr/lib/apache2/modules" "$OUT/etc" "$OUT/usr/local/lib/php" "$OUT/usr/local/etc/php"
cp /usr/sbin/apache2 "$OUT/usr/sbin/"
cp /usr/lib/apache2/modules/libphp.so "$OUT/usr/lib/apache2/modules/"
for m in $MODULES; do cp "/usr/lib/apache2/modules/mod_$m.so" "$OUT/usr/lib/apache2/modules/"; done
cp /etc/mime.types "$OUT/etc/"
cp -a /usr/local/lib/php/extensions "$OUT/usr/local/lib/php/"
cp -a /usr/local/etc/php/conf.d "$OUT/usr/local/etc/php/"

MULTI="$(dirname "$(readlink -f "$(ldd /bin/sh | awk '/libc\.so/ {print $3}')")")"   # e.g. /usr/lib/x86_64-linux-gnu
FILES="$OUT/usr/sbin/apache2 $OUT/usr/lib/apache2/modules/*.so $(ls "$OUT"/usr/local/lib/php/extensions/*/*.so)"

# shellcheck disable=SC2086
ldd $FILES 2>&1 | awk '/not found/ {print "NOT FOUND: " $0 > "/dev/stderr"; bad=1} /=> \// {print $3} END {exit bad}' | sort -u > /libs.txt
test -s /libs.txt

copied=0; skipped=0
while read -r lib; do
  base="$(basename "$lib")"
  if [ -e "$DISTRO$MULTI/$base" ]; then skipped=$((skipped + 1)); continue; fi
  dir="$(dirname "$(readlink -f "$lib")")"
  mkdir -p "$OUT$dir"
  cp -L "$lib" "$OUT$dir/$base"
  copied=$((copied + 1))
done < /libs.txt
echo "closure: $copied libraries copied, $skipped provided by the distroless base"

# Every library must now exist either in the distroless base or in /rootfs
while read -r lib; do
  base="$(basename "$lib")"; dir="$(dirname "$(readlink -f "$lib")")"
  [ -e "$DISTRO$MULTI/$base" ] || [ -e "$OUT$dir/$base" ] || { echo "missing: $lib" >&2; exit 1; }
done < /libs.txt
