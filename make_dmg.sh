#!/bin/zsh
set -e

# Kullanım: ./make_dmg.sh <EXdl.app yolu> <çıktı.dmg>
# Arka planlı ve büyük ikonlu kurulum DMG'sini dmgbuild ile oluşturur.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ne 2 ]; then
    echo "Kullanım: $0 <EXdl.app yolu> <çıktı.dmg>" >&2
    exit 1
fi

APP_BUNDLE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_DMG="$2"
VOLUME_NAME="EXdl"

DMGBUILD_VERSION="1.6.7"
VENV_DIR="$SCRIPT_DIR/.build/dmg-venv"
VENV_MARKER="$VENV_DIR/.dmgbuild-$DMGBUILD_VERSION"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Uygulama paketi bulunamadı: $APP_BUNDLE" >&2
    exit 1
fi

# dmgbuild, .build/ altındaki geçici bir sanal ortama kurulur (git'e girmez, sistemi değiştirmez)
if [ ! -f "$VENV_MARKER" ]; then
    echo "📦 dmgbuild $DMGBUILD_VERSION kuruluyor (yalnızca ilk çalıştırmada)..."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"
    touch "$VENV_MARKER"
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"

"$VENV_DIR/bin/dmgbuild" \
    -s "$SCRIPT_DIR/dmg/settings.py" \
    -D app="$APP_BUNDLE" \
    -D background="$SCRIPT_DIR/dmg/background.png" \
    "$VOLUME_NAME" "$OUTPUT_DMG"

echo "✅ DMG hazır: $OUTPUT_DMG"
