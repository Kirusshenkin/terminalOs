> **Альфа / Alpha.** Версии 0.x — ранние: интерфейс и форматы ещё меняются, а
> приложение не подписано сертификатом Apple. Ошибки — в issues репозитория.
> Early builds: the interface and formats still change, and the app is not
> signed with an Apple certificate. Please report problems in issues.

## Установка

```sh
curl -fsSL https://github.com/Kirusshenkin/terminalOs/releases/latest/download/Phosphor.zip -o Phosphor.zip
unzip -q Phosphor.zip -d /Applications
xattr -dr com.apple.quarantine /Applications/Phosphor.app
```

Приложение подписано ad-hoc, не нотаризовано — поэтому macOS помечает скачанный
архив карантином, и его нужно снять командой выше (или открыть приложение через
правый клик → «Открыть»).

Проверить архив: `shasum -a 256 -c SHA256SUMS.txt`.

## Для агентов

`latest.json` в ассетах релиза содержит версию, ссылку, размер, sha256 и путь к
MCP-шиму. Ничего парсить в HTML не нужно.

Клиенты MCP ставят `phosphor-mcp-<версия>.mcpb` — в нём манифест и тот же шим.
`server.json` рядом описывает сборку для реестра MCP (`io.github.kirusshenkin/phosphor`)
и несёт sha256 бандла: клиент проверяет скачанное до запуска. Бандл — это шим,
а не приложение: без установленного и разблокированного Phosphor вызовы честно
отвечают ошибкой.
