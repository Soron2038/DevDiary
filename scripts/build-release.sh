#!/bin/bash
set -e

# DevDiary Release Build Script
# Creates a .app bundle and DMG installer

# Version source: VERSION file (fallback to 1.0.0)
if [ -f "$(dirname "$0")/../VERSION" ]; then
  VERSION="$(cat "$(dirname "$0")/../VERSION" | tr -d '\n')"
else
  VERSION="1.0.0"
fi
APP_NAME="DevDiary"
BUNDLE_ID="com.devdiary.app"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/Distribution"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "🔨 Building DevDiary $VERSION..."
echo "Project: $PROJECT_DIR"

# Clean previous builds
rm -rf "$APP_BUNDLE"
rm -f "$DIST_DIR/$DMG_NAME"

# Build release
echo "📦 Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

# Create app bundle structure
echo "📁 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$DIST_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Inject version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || true

# Copy and convert app icon
echo "🎨 Processing app icon..."
ICON_SOURCE="$PROJECT_DIR/Assets/AppIcon.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"

if [ -f "$ICON_SOURCE" ]; then
    mkdir -p "$ICONSET_DIR"
    
    # Generate different icon sizes
    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" 2>/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" 2>/dev/null
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" 2>/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" 2>/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" 2>/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null
    
    # Convert to icns
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "   ✓ App icon created"
else
    echo "   ⚠ No app icon found at $ICON_SOURCE"
fi

# Copy resources (localization files, assets)
echo "📋 Copying resources..."
if [ -d "$PROJECT_DIR/Sources/DevDiary/Resources" ]; then
    # Copy .lproj directories for localization
    for lproj in "$PROJECT_DIR/Sources/DevDiary/Resources/"*.lproj; do
        if [ -d "$lproj" ]; then
            cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
            echo "   ✓ Copied $(basename "$lproj")"
        fi
    done
fi

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ App bundle created: $APP_BUNDLE"

# Create DMG
echo "💿 Creating DMG installer..."

# Create temporary DMG directory
DMG_TEMP="$DIST_DIR/dmg_temp"
DMG_RW="$DIST_DIR/${APP_NAME}_rw.dmg"
rm -rf "$DMG_TEMP"
rm -f "$DMG_RW"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create symbolic link to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Copy background image (hidden)
BG_SOURCE="$PROJECT_DIR/Resources/dmg-background.png"
if [ -f "$BG_SOURCE" ]; then
    mkdir -p "$DMG_TEMP/.background"
    cp "$BG_SOURCE" "$DMG_TEMP/.background/background.png"
    echo "   ✓ Background image added"
fi

# Create read-write DMG first (needed for customization)
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDRW \
    "$DMG_RW"

# Mount the DMG
MOUNT_DIR="/Volumes/$APP_NAME"

# Detach if already mounted
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true

hdiutil attach "$DMG_RW" -mountpoint "$MOUNT_DIR" -nobrowse

# Wait for mount
sleep 1

# Set volume icon if available
if [ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

# Use AppleScript to set window properties and icon positions
echo "   Configuring DMG layout..."
osascript <<EOF || echo "   ⚠ AppleScript layout failed (non-critical)"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 540, 380}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        try
            set background picture of viewOptions to file ".background:background.png"
        end try
        try
            set position of item "$APP_NAME.app" of container window to {120, 140}
            set position of item "Applications" of container window to {320, 140}
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Sync filesystem
sync
sleep 1

# Unmount
hdiutil detach "$MOUNT_DIR" -force

# Convert to compressed read-only DMG
hdiutil convert "$DMG_RW" -format UDZO -o "$DIST_DIR/$DMG_NAME" -ov

# Cleanup
rm -rf "$DMG_TEMP"
rm -f "$DMG_RW"

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 App Bundle: $APP_BUNDLE"
echo "💿 DMG Installer: $DIST_DIR/$DMG_NAME"
echo ""
echo "📝 Note: The app is not signed. Users will need to:"
echo "   1. Right-click the app and select 'Open'"
echo "   2. Or allow it in System Settings → Privacy & Security"
