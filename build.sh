#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PyWhat"
EXECUTABLE="PyWhat"
VERSION="${PYWHAT_VERSION:-1.0.0}"
BUNDLE_ID="no.synapse.pywhat.app"
SRC_DIR="$SCRIPT_DIR/PyWhat"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

FRAMEWORKS="-framework SwiftUI -framework AppKit -framework Combine"

SOURCES=(
    "$SRC_DIR/PyWhatApp.swift"
    "$SRC_DIR/ProcessScanner.swift"
    "$SRC_DIR/DesignTokens.swift"
    "$SRC_DIR/PanelView.swift"
    "$SRC_DIR/UpdateService.swift"
)

echo "Klargjør build-mappe..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "Kompilerer $APP_NAME..."
swiftc \
    -O \
    -swift-version 5 \
    -target arm64-apple-macosx13.0 \
    $FRAMEWORKS \
    -parse-as-library \
    "${SOURCES[@]}" \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

echo "Skriver Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ -f "$SCRIPT_DIR/Assets/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
# Seksjonsikoner (SVG) — refereres via asset-feltet i DesignTokens.swift
cp "$SCRIPT_DIR/Assets/"*.svg "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

echo "Signerer (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Installerer til /Applications/$APP_NAME.app ..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"

echo ""
echo "✓ Build ferdig: /Applications/$APP_NAME.app"
echo "  Drift kjøres av launchd: launchctl kickstart -k gui/\$(id -u)/no.synapse.pywhat"
