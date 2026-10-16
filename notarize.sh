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

cp ".build/release/EXdlStubLauncher" "$RESOURCES_DIR/EXdlStubLauncher"
chmod +x "$RESOURCES_DIR/EXdlStubLauncher"
cp ".build/release/EXdlStubLauncher" "$RESOURCES_DIR/HariciKurStubLauncher"
chmod +x "$RESOURCES_DIR/HariciKurStubLauncher"

if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Info.plist ve yerelleştirilmiş izin açıklamaları Support/ klasöründen gelir
sed "s/__VERSION__/$VERSION/" "$SCRIPT_DIR/Support/Info.plist.template" > "$CONTENTS_DIR/Info.plist"
cp -R "$SCRIPT_DIR/Support/en.lproj" "$SCRIPT_DIR/Support/tr.lproj" "$RESOURCES_DIR/"

# 2. Hardened Runtime ve Developer ID ile İmzala
echo "🔏 2/5: Hardened Runtime ile kod imzalanıyor..."
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/EXdlStubLauncher"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/HariciKurStubLauncher"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"

# 3. Dağıtım DMG'sini Hazırla ve İmzala
echo "📦 3/5: Dağıtım DMG'si oluşturuluyor ve imzalanıyor..."
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$DMG_NAME"
./make_dmg.sh "$APP_BUNDLE" "$OUTPUT_DIR/$DMG_NAME"

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
