#!/bin/bash
set -e

# Configuration
APP_NAME="DevDiary"
APP_VERSION="1.2.0"
DMG_NAME="${APP_NAME}_${APP_VERSION}.dmg"
BUILD_DIR=".build/release"
OUTPUT_DIR="Distribution"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "🚀 Starting Build & Package Process..."

# 1. Preserve Icon if exists (since generating from .appiconset without Xcode is hard)
EXISTING_ICON="Distribution/DevDiary.app/Contents/Resources/AppIcon.icns"
TEMP_ICON="/tmp/DevDiaryAppIcon.icns"
if [ -f "$EXISTING_ICON" ]; then
    echo "📦 Preserving existing AppIcon.icns..."
    cp "$EXISTING_ICON" "$TEMP_ICON"
else
    echo "⚠️ No existing icon found at $EXISTING_ICON"
fi

# 2. Clean and Build
echo "🧹 Cleaning..."
# We don't remove everything to avoid re-downloading dependencies, just release build
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "🔨 Building (Release)..."
swift build -c release --arch arm64 --arch x86_64

# Locate binary
# Universal build location might vary, checking common paths
if [ -f ".build/apple/Products/Release/DevDiary" ]; then
    BINARY_PATH=".build/apple/Products/Release/DevDiary"
elif [ -f ".build/release/DevDiary" ]; then
    BINARY_PATH=".build/release/DevDiary"
elif [ -f ".build/arm64-apple-macosx/release/DevDiary" ]; then
    BINARY_PATH=".build/arm64-apple-macosx/release/DevDiary"
else
    # Fallback to finding it
    BINARY_PATH=$(find .build -name "DevDiary" -type f | grep "release" | head -n 1)
fi

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Could not find compiled binary!"
    exit 1
fi
echo "✅ Found binary at $BINARY_PATH"

# 3. Create App Bundle
echo "📂 Creating App Bundle Structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy Binary
cp "$BINARY_PATH" "${APP_BUNDLE}/Contents/MacOS/"

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>DevDiary</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.devdiary.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>DevDiary</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${APP_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Restore Icon
if [ -f "$TEMP_ICON" ]; then
    echo "🖼 Restoring Icon..."
    cp "$TEMP_ICON" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Copy Resources
echo "🌍 Copying Localizations..."
# Direct copy from source as fallback
if [ -d "Sources/DevDiary/Resources/en.lproj" ]; then
    cp -r "Sources/DevDiary/Resources/en.lproj" "${APP_BUNDLE}/Contents/Resources/"
fi
if [ -d "Sources/DevDiary/Resources/de.lproj" ]; then
    cp -r "Sources/DevDiary/Resources/de.lproj" "${APP_BUNDLE}/Contents/Resources/"
fi

# 4. Sign
echo "🔏 Signing App..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 5. Create DMG
echo "💿 Creating DMG..."
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH" # Remove existing
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_BUNDLE}" -ov -format UDZO "${DMG_PATH}"

echo "✅ Package created successfully!"
echo "📍 Location: ${DMG_PATH}"
