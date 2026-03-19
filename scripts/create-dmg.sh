#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <path-to-app>}"
APP_NAME=$(basename "$APP_PATH" .app)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR=$(mktemp -d)

echo "Creating DMG: $DMG_NAME"

# Copy app to temp directory
cp -R "$APP_PATH" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 150 200 \
        --app-drop-link 450 200 \
        "$DMG_NAME" \
        "$DMG_DIR"
else
    echo "create-dmg not found, using hdiutil fallback"
    hdiutil create -volname "$APP_NAME $VERSION" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        "$DMG_NAME"
fi

# Cleanup
rm -rf "$DMG_DIR"

echo "Created: $DMG_NAME"
