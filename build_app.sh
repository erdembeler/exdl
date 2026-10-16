#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="${VERSION:-1.0.0}"

echo "🔨 EXdl ve EXdlStubLauncher derleniyor..."
swift build -c release

APP_NAME="EXdl"
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

# Keychain'de Developer ID varsa onunla imzala (TCC izinlerinin korunması için), yoksa ad-hoc imzala
IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null | grep "Developer ID Application:" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/EXdlStubLauncher"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$RESOURCES_DIR/HariciKurStubLauncher"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "✅ Başarıyla oluşturuldu: $APP_BUNDLE"
