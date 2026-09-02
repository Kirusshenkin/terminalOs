#!/bin/bash
# Готовит то, что кладётся в релиз: zip с приложением, контрольные суммы и
# манифест.
#
# Zip делается через ditto, а не zip(1): обычный zip теряет символические ссылки
# внутри бандла и ad-hoc подпись после распаковки становится недействительной —
# приложение не запускается, и понять почему трудно.
set -euo pipefail
cd "$(dirname "$0")/.."

SHORT="${MARKETING_VERSION:-0.1.0}"
BUILD="${BUILD_NUMBER:-1}"
REPO="${GITHUB_REPOSITORY:-Kirusshenkin/terminalOs}"

MARKETING_VERSION="$SHORT" BUILD_NUMBER="$BUILD" ./scripts/bundle.sh release

ZIP="dist/Phosphor-$SHORT.zip"
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc dist/Phosphor.app "$ZIP"

# Копия без версии в имени: только по точному имени файла работает вечная
# ссылка /releases/latest/download/Phosphor.zip, а её и вставляют в инструкции.
cp "$ZIP" dist/Phosphor.zip

SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
SIZE="$(stat -f%z "$ZIP")"
(cd dist && shasum -a 256 "$(basename "$ZIP")" Phosphor.zip > SHA256SUMS.txt)

# Манифест — то, что читает машина: версия, откуда качать и чем проверить.
# Человеку хватает страницы релиза, агенту нужен один разбираемый файл.
cat > dist/latest.json <<JSON
{
  "name": "Phosphor",
  "version": "$SHORT",
  "build": $BUILD,
  "minimumSystemVersion": "14.0",
  "url": "https://github.com/$REPO/releases/download/v$SHORT/Phosphor-$SHORT.zip",
  "size": $SIZE,
  "sha256": "$SHA",
  "install": "unzip -q Phosphor-$SHORT.zip -d /Applications && xattr -dr com.apple.quarantine /Applications/Phosphor.app",
  "mcp": {
    "command": "/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp",
    "transport": "stdio"
  }
}
JSON

echo "готово:"
echo "  $ZIP  ($(( SIZE / 1024 / 1024 )) МБ)"
echo "  dist/Phosphor.zip" 
echo "  dist/SHA256SUMS.txt"
echo "  dist/latest.json"
