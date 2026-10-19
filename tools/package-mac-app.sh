#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/dist/miaokon-mac-2.2.1.app}"
APP_MODE="${2:-usb}"
APP_DIR="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$APP_DIR")"

case "$APP_MODE" in
  usb) WIFI_DEFAULT=false ;;
  wifi) WIFI_DEFAULT=true ;;
  *) echo "Usage: $0 [output.app] [usb|wifi]" >&2; exit 2 ;;
esac

if [ -e "$APP_DIR" ]; then
  echo "Refusing to overwrite existing app: $APP_DIR" >&2
  exit 1
fi

cd "$ROOT_DIR/TracepadMac"
swift build -c release --product miaokon-mac

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/TracepadMac/.build/release/miaokon-mac" "$APP_DIR/Contents/MacOS/miaokon-mac"
cp "$ROOT_DIR/TracepadMac/Resources/miaokon-mac.icns" "$APP_DIR/Contents/Resources/miaokon-mac.icns"
cp "$ROOT_DIR/TracepadMac/Info.plist" "$APP_DIR/Contents/Info.plist"
plutil -replace MiaokonAndroidWiFiDefault -bool "$WIFI_DEFAULT" "$APP_DIR/Contents/Info.plist"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi

echo "Created $APP_DIR (Android transport: $APP_MODE)"
