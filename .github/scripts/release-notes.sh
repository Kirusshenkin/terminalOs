#!/bin/bash
# Заметки к релизу из истории между тегами: что нового, кто сделал, как
# поставить. GitHub-овский --generate-notes тут бесполезен — он собирает
# слитые PR, а коммиты идут прямо в main.
#
#   release-notes.sh <тег> <номер сборки> [каталог с SHA256SUMS.txt]
set -euo pipefail
cd "$(dirname "$0")/../.."

TAG="$1"
BUILD="$2"
DIST="${3:-dist}"
VERSION="${TAG#v}"
REPO="Kirusshenkin/terminalOs"
PREV=$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)
RANGE="${PREV:+$PREV..}$TAG"

# Строка коммита: тема со ссылкой на сам коммит.
line() { echo "- $2 ([\`${1:0:7}\`](https://github.com/$REPO/commit/$1))"; }

features=""
fixes=""
deps=""
docs=""
while IFS=$'\t' read -r sha subject; do
  [ -z "$sha" ] && continue
  case "$subject" in
    Merge\ *) continue ;;
    Fix* | Stop* | Keep* | Don\'t* | Guard*) fixes+="$(line "$sha" "$subject")"$'\n' ;;
    Plan* | Document* | Teach*) docs+="$(line "$sha" "$subject")"$'\n' ;;
    Bump* | Update| Update\ actions/* | Upgrade*) deps+="$(line "$sha" "$subject")"$'\n' ;;
    *) features+="$(line "$sha" "$subject")"$'\n' ;;
  esac
done < <(git log --no-merges --reverse --format='%H%x09%s' "$RANGE")

# Авторы — только люди: боты и ИИ-ассистенты в благодарности не попадают.
# Адрес вида 123+login@users.noreply.github.com превращается в @login.
authors=$(git log --no-merges --format='%an%x09%ae' "$RANGE" | sort -u | while IFS=$'\t' read -r name email; do
  echo "$name $email" | grep -qiE '\[bot\]|claude|anthropic|copilot|codex|openai|cursor' && continue
  case "$email" in
    (*@users.noreply.github.com) login="${email%@*}"; echo "@${login#*+}" ;;
    (*) echo "$name" ;;
  esac
done | sort -u | paste -sd ' ' - | sed 's/ /, /g')

section() { [ -n "$2" ] && printf '### %s\n\n%s\n' "$1" "$2"; }

# Рукописные заметки, если есть: docs/releases/<тег>.md заменяет список
# коммитов. Темы коммитов пишутся для истории, а не для людей, и в них
# встречаются названия чужих продуктов, которым в описании релиза не место.
HANDWRITTEN="docs/releases/$TAG.md"

cat <<MD
$( [[ "$VERSION" == 0.* ]] && cat <<'ALPHA'
> [!WARNING]
> **Альфа.** Интерфейс и форматы ещё меняются, приложение не подписано сертификатом Apple.
> Ошибки — в [issues](https://github.com/Kirusshenkin/terminalOs/issues).
> **Alpha.** The interface and formats still change; the app is not signed with an Apple certificate.

ALPHA
)

**Phosphor $VERSION** · сборка $BUILD · macOS 26+ · Apple Silicon

Уже стоит Phosphor? Обновление появится в шапке приложения — щёлкни по нему.
Already have Phosphor? The update shows up in the app header — click it.

## Что нового · What's new

$(if [ -f "$HANDWRITTEN" ]; then cat "$HANDWRITTEN"; else
  section "Новое · Changes" "$features"
  section "Исправления · Fixes" "$fixes"
  section "Документация и план · Docs" "$docs"
  section "Зависимости · Dependencies" "$deps"
fi)
${PREV:+**Все изменения · Full changelog:** [\`$PREV...$TAG\`](https://github.com/$REPO/compare/$PREV...$TAG)}
${authors:+

**Сделали · Contributors:** $authors}

## Установка · Install

\`\`\`sh
curl -fsSL https://github.com/$REPO/releases/latest/download/Phosphor.zip -o Phosphor.zip
unzip -q Phosphor.zip -d /Applications
xattr -dr com.apple.quarantine /Applications/Phosphor.app
\`\`\`

Подпись ad-hoc, без нотаризации — поэтому карантин снимается вручную (или правый клик → «Открыть»).
Ad-hoc signed, not notarized — remove the quarantine as above, or right-click → Open.

<details>
<summary>Файлы релиза · Assets</summary>

| Файл | Зачем |
|---|---|
| \`Phosphor.zip\` | приложение, постоянная ссылка на последнюю версию |
| \`Phosphor-$VERSION.zip\` | то же приложение с версией в имени |
| \`latest.json\` + \`.sig\` | манифест обновления и его подпись P-256 — по ним приложение обновляется само |
| \`phosphor-mcp-$VERSION.mcpb\` | MCP-шим для ИИ-клиентов · MCP shim for AI clients |
| \`server.json\` | описание для реестра MCP (\`io.github.kirusshenkin/phosphor\`) |
| \`SHA256SUMS.txt\` | контрольные суммы: \`shasum -a 256 -c SHA256SUMS.txt\` |

$( [ -f "$DIST/SHA256SUMS.txt" ] && printf '```\n%s\n```\n' "$(cat "$DIST/SHA256SUMS.txt")" )
</details>

<details>
<summary>Для агентов · For agents</summary>

\`latest.json\` содержит версию, ссылку, размер и sha256 — ничего парсить в HTML не нужно.
MCP-клиенты ставят \`.mcpb\`; \`server.json\` несёт его sha256, клиент проверяет скачанное до запуска.
Шим — не приложение: без установленного и разблокированного Phosphor вызовы отвечают ошибкой.
</details>
MD
