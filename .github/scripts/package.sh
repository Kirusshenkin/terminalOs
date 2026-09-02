#!/bin/bash
# Готовит то, что кладётся в релиз: zip с приложением, контрольные суммы и
# манифест.
#
# Zip делается через ditto, а не zip(1): обычный zip теряет символические ссылки
# внутри бандла и ad-hoc подпись после распаковки становится недействительной —
# приложение не запускается, и понять почему трудно.
set -euo pipefail
cd "$(dirname "$0")/../.."

SHORT="${MARKETING_VERSION:-0.1.1}"
BUILD="${BUILD_NUMBER:-1}"
REPO="${GITHUB_REPOSITORY:-Kirusshenkin/terminalOs}"

MARKETING_VERSION="$SHORT" BUILD_NUMBER="$BUILD" ./.github/scripts/bundle.sh release

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

# MCP-бандл: то, чем нас ставят клиенты и чем нас находит реестр MCP.
# Внутри — тот же шим, что лежит в приложении: он не носит секретов и умеет
# только пересылать JSON-RPC в сокет запущенного Phosphor.
STAGE="dist/mcpb"
rm -rf "$STAGE" && mkdir -p "$STAGE/server"
cp dist/Phosphor.app/Contents/MacOS/phosphor-mcp "$STAGE/server/phosphor-mcp"

cat > "$STAGE/manifest.json" <<JSON
{
  "manifest_version": "0.3",
  "name": "phosphor",
  "display_name": "Phosphor",
  "version": "$SHORT",
  "description": "Hosts, metrics, Docker and authorized_keys over the SSH connections Phosphor already holds. Requires Phosphor.app on macOS.",
  "author": { "name": "The Phosphor authors", "url": "https://github.com/$REPO" },
  "homepage": "https://github.com/$REPO",
  "documentation": "https://github.com/$REPO/blob/main/docs/MCP.md",
  "license": "MIT",
  "server": {
    "type": "binary",
    "entry_point": "server/phosphor-mcp",
    "mcp_config": {
      "command": "\${__dirname}/server/phosphor-mcp",
      "args": []
    }
  },
  "compatibility": { "platforms": ["darwin"] }
}
JSON

MCPB="dist/phosphor-mcp-$SHORT.mcpb"
rm -f "$MCPB"
(cd "$STAGE" && zip -qr "../$(basename "$MCPB")" manifest.json server)
MCPB_SHA="$(shasum -a 256 "$MCPB" | cut -d' ' -f1)"

# server.json — паспорт для реестра MCP. Хэш обязателен: клиент проверяет
# скачанный бандл прежде, чем что-то запустить.
cat > dist/server.json <<JSON
{
  "\$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "io.github.${REPO%%/*}/phosphor",
  "title": "Phosphor",
  "description": "Hosts, metrics, Docker and authorized_keys over a macOS terminal's live SSH connections",
  "version": "$SHORT",
  "websiteUrl": "https://github.com/$REPO",
  "repository": {
    "url": "https://github.com/$REPO",
    "source": "github"
  },
  "packages": [
    {
      "registryType": "mcpb",
      "identifier": "https://github.com/$REPO/releases/download/v$SHORT/phosphor-mcp-$SHORT.mcpb",
      "version": "$SHORT",
      "fileSha256": "$MCPB_SHA",
      "transport": { "type": "stdio" }
    }
  ]
}
JSON

(cd dist && shasum -a 256 "$(basename "$MCPB")" >> SHA256SUMS.txt)

echo "готово:"
echo "  $ZIP  ($(( SIZE / 1024 / 1024 )) МБ)"
echo "  dist/Phosphor.zip" 
echo "  dist/SHA256SUMS.txt"
echo "  dist/latest.json"
echo "  $MCPB"
echo "  dist/server.json"
