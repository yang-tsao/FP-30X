#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Building release executable ==="
swift build -c release

APP_NAME="FP-30X Controller"
APP_DIR="build/${APP_NAME}.app"
EXECUTABLE="RolandFP30XController"
EXE=".build/release/${EXECUTABLE}"

if [ ! -f "$EXE" ]; then
    echo "ERROR: Executable not found: $EXE"
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXE" "$APP_DIR/Contents/MacOS/"

# ── Info.plist ────────────────────────────────────────────────────────────────
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RolandFP30XController</string>
    <key>CFBundleIdentifier</key>
    <string>com.fp30x.controller</string>
    <key>CFBundleName</key>
    <string>FP-30X Controller</string>
    <key>CFBundleDisplayName</key>
    <string>FP-30X Controller</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# ── App icon ──────────────────────────────────────────────────────────────────
ICONSET="/tmp/fp30x_icon.iconset"
SVG="Sources/RolandFP30XController/Resources/app_icon.svg"
if command -v rsvg-convert &>/dev/null && [ -f "$SVG" ]; then
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        rsvg-convert -w $s -h $s "$SVG" -o "$ICONSET/icon_${s}x${s}.png"
    done
    for s in 32 128 256 512; do
        d=$((s*2))
        cp "$ICONSET/icon_${s}x${s}.png" "$ICONSET/icon_${s}x${s}@2x.png"
    done
    iconutil -c icns -o "$APP_DIR/Contents/Resources/app_icon.icns" "$ICONSET"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string app_icon" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile app_icon" "$APP_DIR/Contents/Info.plist"
    rm -rf "$ICONSET"
    echo "  icon: embedded from $SVG"
else
    echo "  icon: none (install librsvg to embed: brew install librsvg)"
fi

# ── DMG ────────────────────────────────────────────────────────────────────────
DMG_NAME="FP-30XController"
DMG_PATH="build/${DMG_NAME}.dmg"
DMG_TMP="build/_dmg_tmp"

rm -rf "$DMG_TMP" "$DMG_PATH"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

echo ""
echo "=== Creating DMG ==="
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TMP"

echo ""
echo "=== Done: $APP_DIR | $DMG_PATH ==="
echo ""
echo "  Copy to /Applications"
echo "  cp -R \"$APP_DIR\" /Applications/"
echo ""
echo "  Or run directly"
echo "  open \"$APP_DIR\""
