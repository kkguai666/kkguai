#!/usr/bin/env bash
# Packages build/kkguai.app as a drag-to-Applications DMG plus a plain zip for a GitHub release.
# usage: scripts/package-release.sh [version]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/kkguai.app/Contents/Info.plist)}"
APP="build/kkguai.app"
DMG="build/kkguai-${VERSION}-macos-arm64.dmg"
ZIP="build/kkguai-${VERSION}-macos-arm64.zip"

[ -d "$APP" ] || { echo "先运行 ./scripts/build-app.sh --no-install" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# The volume holds the app and a shortcut to /Applications, so installing is one drag.
ditto "$APP" "$STAGE/kkguai.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$ZIP"
hdiutil create -quiet -volname "kkguai" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Same identity as the app, so the disk image itself verifies cleanly.
SIGN_ID="kkguai Self-Signed"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
	codesign --force --sign "$SIGN_ID" "$DMG" >/dev/null
fi

echo "$DMG"
echo "$ZIP"
