#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="1.1.0"
APP_NAME="EXdl"
DMG_NAME="$APP_NAME-$VERSION.dmg"
ZIP_NAME="$APP_NAME-$VERSION.zip"
OUTPUT_DIR="$SCRIPT_DIR/dist"

echo "EXdl v$VERSION yayın paketi hazırlanıyor..."

# 1. Uygulamayı derle ve paketle
./build_app.sh

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$DMG_NAME" "$OUTPUT_DIR/$ZIP_NAME"

# 2. Arka planlı, büyük ikonlu kurulum DMG'sini oluştur
echo "Dağıtım DMG'si oluşturuluyor ($DMG_NAME)..."
./make_dmg.sh "$SCRIPT_DIR/$APP_NAME.app" "$OUTPUT_DIR/$DMG_NAME"

# 3. Alternatif ZIP arşivi de oluştur (Doğrudan indirmeler ve GitHub Release için)
echo "ZIP arşivi oluşturuluyor ($ZIP_NAME)..."
ditto -c -k --sequesterRsrc --keepParent "$SCRIPT_DIR/$APP_NAME.app" "$OUTPUT_DIR/$ZIP_NAME"

echo ""
echo "=================================================="
echo "EXdl v$VERSION Başarıyla Paketlendi!"
echo "Dağıtım Dosyaları ($OUTPUT_DIR/):"
ls -lh "$OUTPUT_DIR"
echo "=================================================="
