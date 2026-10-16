#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TEAM_ID="CL2XB7QHS4"
IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')

if [ -z "$IDENTITY" ]; then
    echo "⚠️  'Developer ID Application' sertifikası anahtar zincirinde bulunamadı."
    echo "Lütfen Xcode -> Settings -> Accounts -> Manage Certificates altından '+' butonuna basıp 'Developer ID Application' sertifikası ekleyin."
    exit 1
fi

echo "🔐 İmzalama kimliği: $IDENTITY"
VERSION="1.0.0"
DMG_NAME="HariciKur-$VERSION.dmg"
OUTPUT_DIR="$SCRIPT_DIR/dist"
STAGE_DIR="$SCRIPT_DIR/.build/dmg_stage"

# 1. Derle
echo "🔨 HariciKur derleniyor..."
swift build -c release

APP_NAME="HariciKur"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp ".build/release/HariciKurStubLauncher" "$RESOURCES_DIR/HariciKurStubLauncher"
chmod +x "$RESOURCES_DIR/HariciKurStubLauncher"

if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HariciKur</string>
    <key>CFBundleIdentifier</key>
    <string>com.erdem.HariciKur</string>
    <key>CFBundleName</key>
    <string>HariciKur</string>
    <key>CFBundleDisplayName</key>
    <string>HariciKur</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 2. Hardened Runtime ve Zaman Damgası ile İmzala
echo "🔏 Hardened Runtime ile kod imzalanıyor..."
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/HariciKurStubLauncher"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"

# 3. DMG Oluştur
echo "📦 DMG oluşturuluyor..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$DMG_NAME"
hdiutil create -volname "HariciKur" -srcfolder "$STAGE_DIR" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME"
rm -rf "$STAGE_DIR"

# DMG'yi de imzala
codesign --force --timestamp --sign "$IDENTITY" "$OUTPUT_DIR/$DMG_NAME"

echo ""
echo "✅ $OUTPUT_DIR/$DMG_NAME başarıyla imzalandı!"
echo "📡 Apple Noter Onayına (Notarization) Göndermek İçin:"
echo "   xcrun notarytool submit \"$OUTPUT_DIR/$DMG_NAME\" --keychain-profile \"AC_PASSWORD\" --wait"
echo "   xcrun stapler staple \"$OUTPUT_DIR/$DMG_NAME\""
