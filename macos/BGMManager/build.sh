#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_DIR/dist/BGM Manager.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$SCRIPT_DIR/AppIcon.icns"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"

clang \
    -fobjc-arc \
    "$SCRIPT_DIR/App.m" \
    -framework Cocoa \
    -o "$MACOS_DIR/BGMManager"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BGMManager</string>
    <key>CFBundleIdentifier</key>
    <string>local.bgm-manager</string>
    <key>CFBundleName</key>
    <string>BGM Manager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>RepositoryPath</key>
    <string>$REPO_DIR</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
