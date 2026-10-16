#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TEAM_ID="DXBCHW6VWL"
KEYCHAIN_PROFILE="Exdl"

IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')

if [ -z "$IDENTITY" ]; then
    echo "❌ 'Developer ID Application' sertifikası anahtar zincirinde bulunamadı."
    exit 1
fi

echo "🔐 Geliştirici İmzası: $IDENTITY"
echo "🔑 Noter Profili: $KEYCHAIN_PROFILE (Takım ID: $TEAM_ID)"

VERSION="1.0.0"
APP_NAME="EXdl"
DMG_NAME="EXdl-$VERSION.dmg"
OUTPUT_DIR="$SCRIPT_DIR/dist"
STAGE_DIR="$SCRIPT_DIR/.build/dmg_stage"

# 1. Swift ile Derleme
echo "🔨 1/5: EXdl derleniyor..."
swift build -c release

APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
pkill -f "HariciKur" 2>/dev/null || true
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp ".build/release/EXdlStubLauncher" "$RESOURCES_DIR/HariciKurStubLauncher"
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
    <string>EXdl</string>
    <key>CFBundleIdentifier</key>
    <string>com.erdem.EXdl</string>
    <key>CFBundleName</key>
    <string>EXdl</string>
    <key>CFBundleDisplayName</key>
    <string>EXdl</string>
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

# 2. Hardened Runtime ve Developer ID ile İmzala
echo "🔏 2/5: Hardened Runtime ile kod imzalanıyor..."
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/HariciKurStubLauncher"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"

# 3. Dağıtım DMG'sini Hazırla ve İmzala
echo "📦 3/5: Dağıtım DMG'si oluşturuluyor ve imzalanıyor..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$DMG_NAME"
hdiutil create -volname "EXdl" -srcfolder "$STAGE_DIR" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME"
rm -rf "$STAGE_DIR"

codesign --force --timestamp --sign "$IDENTITY" "$OUTPUT_DIR/$DMG_NAME"

# 4. Apple Noter Servisine Gönder
echo "📡 4/5: Apple Noter Onayına (Notarization) iletiliyor (bu işlem 1-2 dakika sürebilir)..."
xcrun notarytool submit "$OUTPUT_DIR/$DMG_NAME" --keychain-profile "$KEYCHAIN_PROFILE" --wait

# 5. Onay Damgasını (Ticket) DMG'ye Zımbala
echo "🏷️  5/5: Apple onay bileti DMG'ye zımbalanıyor (Stapling)..."
xcrun stapler staple "$OUTPUT_DIR/$DMG_NAME"

# Gatekeeper Doğrulama Kontrolü
echo ""
echo "🔍 Gatekeeper Doğrulama Testi:"
spctl -a -t open --context context:primary-signature -v "$OUTPUT_DIR/$DMG_NAME"

echo ""
echo "=================================================="
echo "🎉 EXdl v$VERSION Apple Tarafından Başarıyla Noterlendi!"
echo "📍 Onaylı Kurulum Dosyası: $OUTPUT_DIR/$DMG_NAME"
echo "=================================================="
