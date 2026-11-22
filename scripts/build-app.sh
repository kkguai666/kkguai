#!/bin/bash
# Builds kkguai.app (release) with its Dock icon and bundled FreeRDP/OpenSSL, and installs it to
# /Applications. Pin this app in the Dock instead of the bare PstscAgent binary: a bare binary
# shows the generic "exec" icon whenever kkguai is not running.
# 사용법: scripts/build-app.sh [--no-install]
set -euo pipefail

cd "$(dirname "$0")/.."
deps="build/deps/freerdp"
[ -f "$deps/lib/libfreerdp0.0.1.1.dylib" ] || scripts/build-freerdp.sh
swift build -c release
bin="$(swift build -c release --show-bin-path)"

app="build/kkguai.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/PstscAgent" "$bin/PstscDockProxy" "$app/Contents/MacOS/"

# Bundle FreeRDP and OpenSSL; every reference between them goes through @rpath.
frameworks="$app/Contents/Frameworks"
mkdir -p "$frameworks"
# src:dest — dest must equal the install name the binaries link against.
libs="libfreerdp0.0.1.1.dylib:libfreerdp0.0.dylib libfreerdp-client0.0.1.1.dylib:libfreerdp-client0.0.dylib libwinpr0.0.1.1.dylib:libwinpr0.0.dylib libssl.3.dylib:libssl.3.dylib libcrypto.3.dylib:libcrypto.3.dylib"
for pair in $libs; do
    src="${pair%%:*}"; dst="${pair##*:}"
    cp -L "$deps/lib/$src" "$frameworks/$dst"
    chmod u+w "$frameworks/$dst"
    install_name_tool -id "@rpath/$dst" "$frameworks/$dst" 2>/dev/null
done
# The development rpath points into this checkout; the app only uses Contents/Frameworks.
install_name_tool -delete_rpath "$PWD/$deps/lib" "$app/Contents/MacOS/PstscAgent"
cp "$deps/../FreeRDP-"*/LICENSE "$app/Contents/Resources/LICENSE-FreeRDP.txt"
cp "$deps/../openssl-"*/LICENSE.txt "$app/Contents/Resources/LICENSE-OpenSSL.txt"

iconset="build/AppIcon.iconset"
rm -rf "$iconset"
"$bin/PstscAgent" --write-iconset "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>kkguai</string>
	<key>CFBundleDisplayName</key><string>kkguai</string>
	<key>CFBundleIdentifier</key><string>com.pstsc.agent</string>
	<key>CFBundleExecutable</key><string>PstscAgent</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.2.3</string>
	<key>CFBundleVersion</key><string>9</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A stable identity matters: an ad-hoc signature changes with every build, so macOS treats each
# rebuild as a new app and asks for the login password before handing over the saved RDP password.
# With a fixed certificate the Keychain "Always Allow" answer keeps working across builds.
SIGN_ID="kkguai Self-Signed"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID" || SIGN_ID="-"

codesign --force --sign "$SIGN_ID" "$frameworks"/*.dylib >/dev/null
codesign --force --sign "$SIGN_ID" "$app" >/dev/null

[ "${1:-}" = "--no-install" ] && { echo "Built: $app"; exit 0; }
rm -rf "/Applications/kkguai.app"
cp -R "$app" "/Applications/kkguai.app"
echo "설치됨 / Installed / インストール完了: /Applications/kkguai.app"
