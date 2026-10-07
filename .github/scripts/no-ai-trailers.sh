#!/bin/bash
# Нет ли в сообщениях коммитов следов ИИ-ассистентов: соавторства, подписи
# «Generated with», ссылки на сессию. Авторы-люди и боты зависимостей — можно.
#
#   no-ai-trailers.sh <файл сообщения>   — для хука commit-msg
#   no-ai-trailers.sh --range <диапазон> — для проверки истории
set -euo pipefail
PATTERN='^(co-authored-by|generated-by|assisted-by):.*(claude|anthropic|copilot|codex|openai|chatgpt|gemini|cursor)|generated with \[?(claude|copilot|codex)|noreply@anthropic\.com|claude\.ai/code'

if [ "${1:-}" = "--range" ]; then
  bad=$(git log --format='%h %an <%ae>%n%B%x00' "$2" | tr '\0' '\n' | grep -iE "$PATTERN|^[0-9a-f]{7,} [^<]*(claude|anthropic)[^<]*<|^[0-9a-f]{7,} [^<]*<[^>]*(claude|anthropic)[^>]*>$" || true)
else
  bad=$(grep -iE "$PATTERN" "$1" || true)
fi
if [ -n "$bad" ]; then
  echo "✗ след ИИ в коммите — убери строку:" >&2
  echo "$bad" >&2
  exit 1
fi
