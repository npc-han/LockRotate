#!/bin/bash
# Builds build/LockRotate.app from the SwiftPM package and signs it ad-hoc.
#
# Usage: scripts/build-app.sh
#   VERSION=1.2.3 scripts/build-app.sh      # written to CFBundleShortVersionString (default 0.1.0)
#   BUILD_NUMBER=7 scripts/build-app.sh     # written to CFBundleVersion (default 1)
#
# The signature is ad-hoc ("codesign --sign -"), so no developer certificate is needed and the
# result is not notarized. Gatekeeper will ask the user to allow it on first launch.
#
# Resource bundles: SwiftPM's generated Bundle.module accessor looks for
# "LockRotate_<Target>.bundle" in Bundle.main.resourceURL first, which is
# LockRotate.app/Contents/Resources. Putting the bundles there is the standard
# place, and codesign accepts it (bundles at the .app root make --deep signing fail).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LockRotate"
EXECUTABLE="LockRotateApp"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
case "$VERSION" in
    ''|*[!0-9A-Za-z.+-]*) echo "error: VERSION '$VERSION' may only contain letters, digits, '.', '+' and '-'" >&2; exit 64 ;;
esac
case "$BUILD_NUMBER" in
    ''|*[!0-9.]*) echo "error: BUILD_NUMBER '$BUILD_NUMBER' must be digits and dots" >&2; exit 64 ;;
esac
APP="$ROOT/build/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

shopt -s nullglob
bundles=("$BIN_DIR"/LockRotate_*.bundle)
if [ ${#bundles[@]} -eq 0 ]; then
    echo "error: no LockRotate_*.bundle resource bundles in $BIN_DIR" >&2
    exit 1
fi
for bundle in "${bundles[@]}"; do
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>app.lockrotate.LockRotate</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# SwiftPM names each resource bundle's CFBundleIdentifier after the checkout directory
# (for example "111.LockRotateApp.resources"). Give them stable identifiers before signing.
for bundle in "$APP"/Contents/Resources/LockRotate_*.bundle; do
    target="$(basename "$bundle" .bundle)"
    target="${target#LockRotate_}"
    plist="$bundle/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.lockrotate.LockRotate.$target" "$plist"
    plutil -lint "$plist"
done

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Done: $APP"
