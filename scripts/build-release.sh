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
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create symbolic link to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 App Bundle: $APP_BUNDLE"
echo "💿 DMG Installer: $DIST_DIR/$DMG_NAME"
echo ""
echo "📝 Note: The app is not signed. Users will need to:"
echo "   1. Right-click the app and select 'Open'"
echo "   2. Or allow it in System Settings → Privacy & Security"
