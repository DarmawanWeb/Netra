#!/usr/bin/env bash
# Build the NETRA Debian/Ubuntu package from a netra binary:
#   packaging/linux/build-deb.sh <netra binary> <version> <amd64|arm64> [out dir]
# The package depends on the distribution's PostgreSQL; its postinst creates the database.
set -euo pipefail

BIN=${1:?netra binary}
VERSION=${2:?version, e.g. 1.2.0}
ARCH=${3:?amd64 or arm64}
OUT=${4:-dist}
MAINTAINER=${MAINTAINER:-EZRA Robotics <developer@ezrarobotics.id>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION=${VERSION#v}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
chmod 0755 "$STAGE"
install -D -m 0755 "$BIN" "$STAGE/usr/bin/netra"
install -D -m 0644 "$HERE/netra.service" "$STAGE/lib/systemd/system/netra.service"
install -D -m 0640 "$HERE/netra.env" "$STAGE/etc/netra/netra.env"
install -D -m 0644 "$HERE/../../INSTALL.md" "$STAGE/usr/share/doc/netra/INSTALL.md"
install -d "$STAGE/DEBIAN"
install -m 0755 "$HERE/debian/postinst" "$HERE/debian/prerm" "$HERE/debian/postrm" "$STAGE/DEBIAN/"
echo /etc/netra/netra.env > "$STAGE/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: netra
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: postgresql (>= 14) | postgresql-17 | postgresql-16 | postgresql-15 | postgresql-14, adduser, passwd
Recommends: postgresql-contrib
Installed-Size: $SIZE
Section: net
Priority: optional
Homepage: https://github.com/DarmawanWeb/Netra
Description: NETRA patrol command center
 The command center for patrol and inspection robots: live fleet and map, patrols and
 schedules, inspections, reports and the integration API, as one service with its dashboard.
 Open the server in a browser after installing to finish the setup.
CONTROL
mkdir -p "$OUT"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT/netra_${VERSION}_${ARCH}.deb" >/dev/null
echo "$OUT/netra_${VERSION}_${ARCH}.deb"
