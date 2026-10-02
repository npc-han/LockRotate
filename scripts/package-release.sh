#!/bin/bash
# Builds the app and packs it into a release zip plus a SHA-256 file.
#
# Usage: scripts/package-release.sh
#   VERSION=1.2.3 scripts/package-release.sh     # default 0.1.0
#
# Output:
#   build/LockRotate-<version>-macos.zip
#   build/LockRotate-<version>-macos.zip.sha256   (same format as `shasum -a 256`; check with
#                                                  `cd build && shasum -a 256 -c <file>`)
#
# The app inside is ad-hoc signed and not notarized (see scripts/build-app.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export VERSION="${VERSION:-0.1.0}"
APP="$ROOT/build/LockRotate.app"
ZIP_NAME="LockRotate-$VERSION-macos.zip"
ZIP="$ROOT/build/$ZIP_NAME"

"$ROOT/scripts/build-app.sh"

echo "==> Creating $ZIP_NAME"
rm -f "$ZIP" "$ZIP.sha256"
# --keepParent keeps "LockRotate.app" as the top-level entry. --norsrc/--noextattr leave out
# local extended attributes (com.apple.provenance etc.), which ditto would otherwise store as
# "._*" AppleDouble files in the zip; the code signature does not depend on them.
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"

# Run from build/ so the file records the bare zip name, which `shasum -c` can find next to it.
(cd "$ROOT/build" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo "==> Done"
ls -l "$ZIP"
cat "$ZIP.sha256"
