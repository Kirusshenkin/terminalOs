#!/bin/bash
# Собирает Phosphor.app из продукта SwiftPM.
#
# Ad-hoc подпись обязательна: на Apple Silicon неподписанный бинарь просто не
# запустится. Она не убирает предупреждение Gatekeeper при первом скачивании —
# это лечится инструкцией и Homebrew, — но обновления через Sparkle приходят уже
# без карантина.
set -euo pipefail
cd "$(dirname "$0")/../.."

CONFIG="${1:-release}"
SHORT="${MARKETING_VERSION:-0.1.0}"
BUILD="${BUILD_NUMBER:-1}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/Phosphor.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Phosphor" "$APP/Contents/MacOS/Phosphor"
# Шим лежит рядом: MCP-клиент запускает его по пути внутри бандла.
cp "$BIN_DIR/phosphor-mcp" "$APP/Contents/MacOS/phosphor-mcp"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
sed -e "s|__SHORT_VERSION__|$SHORT|" -e "s|__BUILD_VERSION__|$BUILD|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"

echo "собрано: $APP  ($SHORT build $BUILD)"
