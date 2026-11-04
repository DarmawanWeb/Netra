#!/usr/bin/env bash
# Build the NETRA installer for macOS (on a Mac):
#   packaging/macos/build-pkg.sh <netra universal binary> <version> <pgsql dir> [out dir]
# <pgsql dir> holds PostgreSQL's bin/, lib/ and share/ for macOS. The package is not signed:
# first open it with right-click > Open, or sign it with productsign and a Developer ID.
set -euo pipefail

BIN=${1:?netra binary}
VERSION=${2:?version}
PGSQL=${3:?PostgreSQL binaries directory}
OUT=${4:-dist}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION=${VERSION#v}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
install -d "$ROOT/Library/NETRA" "$ROOT/Library/LaunchDaemons"
install -m 0755 "$BIN" "$ROOT/Library/NETRA/netra"
cp -R "$PGSQL" "$ROOT/Library/NETRA/pgsql"
install -m 0644 "$HERE/../../INSTALL.md" "$ROOT/Library/NETRA/INSTALL.md"
install -m 0644 "$HERE/id.ezrarobotics.netra.plist" "$ROOT/Library/LaunchDaemons/"
mkdir -p "$OUT"
pkgbuild --root "$ROOT" --scripts "$HERE/scripts" --identifier id.ezrarobotics.netra --version "$VERSION" \
    --install-location / "$OUT/NETRA-$VERSION-macos.pkg"
echo "$OUT/NETRA-$VERSION-macos.pkg"
