#!/usr/bin/env bash
# Builds "IBA KeyMorph.app" (universal arm64 + x86_64) and a zip next to it in macos/build/.
#   VERSION=1.2.0 ./build-app.sh
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./build-app.sh   # default: ad-hoc signature
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_DIR="build"
APP="$BUILD_DIR/IBA KeyMorph.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IBAKeyMorph" "$APP/Contents/MacOS/IBAKeyMorph"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp ../data/en.txt ../data/ru.txt "$APP/Contents/Resources/"
cp ../assets/panda-logo.png "$APP/Contents/Resources/"

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" ../assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" ../assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --verbose "$APP"

ZIP="$BUILD_DIR/IBA-KeyMorph-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP and $ZIP"
