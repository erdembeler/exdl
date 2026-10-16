#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="1.0.0"
APP_NAME="EXdl"
DMG_NAME="$APP_NAME-$VERSION.dmg"
ZIP_NAME="$APP_NAME-$VERSION.zip"
STAGE_DIR="$SCRIPT_DIR/.build/dmg_stage"
OUTPUT_DIR="$SCRIPT_DIR/dist"

echo "EXdl v$VERSION yayın paketi hazırlanıyor..."

# 1. Uygulamayı derle ve paketle
./build_app.sh

mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGE_DIR" "$OUTPUT_DIR/$DMG_NAME" "$OUTPUT_DIR/$ZIP_NAME"
mkdir -p "$STAGE_DIR"

# 2. DMG hazırlık klasörüne uygulamayı ve /Applications kısayolunu ekle
echo "DMG içeriği hazırlanıyor..."
cp -R "$SCRIPT_DIR/$APP_NAME.app" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

# 3. hdiutil ile sıkıştırılmış DMG imajını oluştur
echo "Dağıtım DMG'si oluşturuluyor ($DMG_NAME)..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME"

# 4. Alternatif ZIP arşivi de oluştur (Doğrudan indirmeler ve GitHub Release için)
echo "ZIP arşivi oluşturuluyor ($ZIP_NAME)..."
ditto -c -k --sequesterRsrc --keepParent "$SCRIPT_DIR/$APP_NAME.app" "$OUTPUT_DIR/$ZIP_NAME"

rm -rf "$STAGE_DIR"

echo ""
echo "=================================================="
echo "EXdl v$VERSION Başarıyla Paketlendi!"
echo "Dağıtım Dosyaları ($OUTPUT_DIR/):"
ls -lh "$OUTPUT_DIR"
echo "=================================================="
