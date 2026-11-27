#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
PACKAGE_ROOT="$ROOT/build/deb-package"
OUTPUT_DIR="$ROOT/build/installers"
OUTPUT="$OUTPUT_DIR/mine-me_0.2.0_amd64.deb"

if [[ ! -x "$BUNDLE/mine_me_native" ]]; then
  echo "Flutter Linux release bundle not found: $BUNDLE" >&2
  exit 1
fi
if [[ ! -f "$BUNDLE/libmine_me_randomx.so" ]]; then
  echo "Native RandomX library is missing from the Linux bundle." >&2
  exit 1
fi

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/usr/lib/mine-me" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications"
mkdir -p "$OUTPUT_DIR"
cp -a "$BUNDLE/." "$PACKAGE_ROOT/usr/lib/mine-me/"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<'CONTROL'
Package: mine-me
Version: 0.2.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: MINE-ME
Depends: libgtk-3-0, libblkid1, liblzma5, libsecret-1-0
Description: MINE-ME native Monero RandomX client
 Member sign-in, device management and authenticated central-pool mining client.
CONTROL

cat > "$PACKAGE_ROOT/usr/bin/mine-me" <<'LAUNCHER'
#!/bin/sh
exec /usr/lib/mine-me/mine_me_native "$@"
LAUNCHER
chmod 0755 "$PACKAGE_ROOT/usr/bin/mine-me"

cat > "$PACKAGE_ROOT/usr/share/applications/mine-me.desktop" <<'DESKTOP'
[Desktop Entry]
Name=MINE-ME
Comment=MINE-ME member mining client
Exec=/usr/bin/mine-me
Terminal=false
Type=Application
Categories=Utility;Network;
DESKTOP

dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$OUTPUT"
echo "Created $OUTPUT"
