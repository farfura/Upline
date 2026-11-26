#!/usr/bin/env bash
# Builds Upline.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Upline.app"
echo "▸ Compiling (release)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Upline"

echo "▸ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Upline"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Building icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad hoc)"
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Upline 2>/dev/null || true
  rm -rf /Applications/Upline.app
  cp -R "$APP" /Applications/
  open /Applications/Upline.app
  echo "✓ Installed to /Applications and launched. Look for the radar in your menu bar."
fi
