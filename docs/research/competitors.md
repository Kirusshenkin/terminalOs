# Конкурентный анализ: Phosphor и рынок SSH/терминала (сентябрь 2026)

## Исследованные конкуренты

### 1. **Termius** — SSH клиент с облаком и командами
- **Платформы:** macOS, Windows, Linux, iOS, Android
- **Плюсы:** интуитивный UI, SFTP-панель, синхронизация по облаку, команды (общие серверы), мобильные приложения на уровне
- **Минусы:** дорого ($10/мес Pro за SFTP/облако), обязательный аккаунт (пользователи жалуются), экспорт ключей сложный, цена отпугивает
- **Клавиши:** стандартные
- **AI:** нет
- **Рейтинг:** 4.6/5 от 59K отзывов, но недовольство ценой и аккаунтом
- **Источники:** [Capterra](https://www.capterra.com/p/234457/Termius/reviews/), [FindStack](https://findstack.com/products/termius/reviews), [MakerStack](https://makerstack.co/reviews/termius-review/)

### 2. **Warp** — AI-терминал с открытым исходным кодом
- **Платформы:** macOS, Windows (2025)
- **Плюсы:** AI (inline генерация, объяснение ошибок), Agents 3.0 (full terminal use, /plan, code review), MCP-серверы поддерживаются, открытый код (AGPL), активная разработка, интеграция Slack/Linear/GitHub Actions
- **Минусы:** нет встроенных SSH сессий (работает через обычный ssh), не так сбалансирован как терминал, overhead от Electron-подобной архитектуры
- **Клавиши:** Ctrl+Shift+N (вкладка), Cmd+K (palette)
- **AI:** ✓ strong — agents, code generation, error explanation
- **Источники:** [Help Net Security](https://www.helpnetsecurity.com/2026/04/30/warp-open-source-client/), [Warp GitHub](https://github.com/warpdotdev/warp), [Warp docs 2026](https://docs.warp.dev/changelog/2026/)

### 3. **iTerm2** — мощный терминал только для macOS
- **Платформы:** macOS
- **Плюсы:** сплиты, вкладки, Growl-уведомления, Instant Replay (скроллбэк), профили, word suggestion (Cmd+;), полная кастомизация клавиш, глобальный hotkey
- **Минусы:** терминал, НЕ SSH клиент; SSH только через команду ssh; нет AI; нет встроенных сессий
- **Клавиши:** Cmd+левая/правая (вкладки), Cmd-{/} (вкладки), Cmd+Option+стрелки (сплиты), Cmd+; (suggestions)
- **AI:** нет
- **Источники:** [iTerm2 docs](https://iterm2.com/features.html), [ShortcutRef](https://shortcutref.com/en/iterm2/)

### 4. **Ghostty** — современный нативный эмулятор (кросс-платформа)
- **Платформы:** macOS (SwiftUI + Metal), Linux (GTK)
- **Плюсы:** нативная реализация, GPU-ускорение, zero-config, системная интеграция (systemd на Linux), темная/светлая синхронизация, Kitty graphics protocol, современные протоколы (clipboard sequences, synchronized rendering), быстрый запуск
- **Минусы:** не SSH клиент, терминал только; нет AI; требует сборки из исходников на Linux
- **Клавиши:** стандартные для системы
- **AI:** нет
- **Статус:** v1.3.0 (март 2026), стабилен, под Hack Club 501(c)(3)
- **Источники:** [Ghostty.org](https://ghostty.org/), [GitHub](https://github.com/ghostty-org), [Petronella Tech](https://petronellatech.com/blog/ghostty-terminal-emulator-setup-configuration-guide-2026/)

### 5. **WezTerm** — SSH с multiplexing и Lua
- **Платформы:** macOS, Windows, Linux
- **Плюсы:** SSH как first-class (SSH domains), Lua config, мультиплексинг (tabs/panes переживают разрыв), прямое определение удалённых хостов, ControlMaster SSH, быстро
- **Минусы:** SSH сессии НЕ стойкие на разрыв (рекомендует свой mux), конфиг на Lua, сложнее чем iTerm2
- **Клавиши:** CTRL+Shift+N (вкладка), CTRL+Shift+W (закрыть), кастомизируется в Lua
- **AI:** нет
- **Источники:** [WezTerm docs SSH](https://wezterm.org/ssh.html), [WezTerm multiplexing](https://wezterm.org/multiplexing.html), [mwop.net howto](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html)

### 6. **Tabby** — Electron: SSH + serial + terminal = всё вместе
- **Платформы:** macOS, Windows, Linux
- **Плюсы:** всё в одном (SSH, serial, terminal), профили SSH, SFTP-панель рядом с шеллом, drag-drop файлы, плагины, таб/сплит, session persistence
- **Минусы:** **Electron = 200–400 МБ RAM** (тяжело), медленнее чем нативное, требует плагины для SSH полноты
- **Клавиши:** кастомизируется
- **AI:** нет
- **Источники:** [MakerStack](https://makerstack.co/reviews/tabby-terminal-review/), [Termique vs Tabby](https://termique.app/vs/tabby/), [X-CMD](https://www.x-cmd.com/install/tabby/)

### 7. **Wave Terminal** — Electron + AI + durable SSH
- **Платформы:** macOS, Windows, Linux (Electron)
- **Плюсы:** AI context-aware (читает вывод, анализирует виджеты), файловое дерево + SSH в одном, durable sessions (переживают разрыв), WSL, remote file editing с графическим редактором, работает с OpenAI/Claude/Gemini/Ollama
- **Минусы:** Electron (memory overhead), AI требует API-ключ (не встроенный Claude)
- **Клавиши:** не ясно из поиска
- **AI:** ✓ strong — Wave AI assistant, любой LLM через API
- **Источники:** [OpenReplay](https://blog.openreplay.com/warp-wave-terminal-ai-powered/), [Wave Terminal](https://www.waveterm.dev/), [Stork.AI review](https://www.stork.ai/en/wave-terminal)

### 8. **Royal TSX** — macOS, multi-protocol управление
- **Платформы:** macOS
- **Плюсы:** SSH/VNC/RDP/Telnet в одном, team collaboration, документы с наследованием, управление ключами, automation (задачи на нескольких), tunneling
- **Минусы:** требует плагин + документ + setup (сложно для новичка), платная ($49 one-time), бесплатная только для 10 подключений
- **AI:** нет
- **Источники:** [Royal Apps](https://royalapps.com/ts/mac/features), [Conduit](https://www.conduitdesktop.com/blog/best-ssh-clients-for-mac), [SSHive](https://sshive.app/en/best-ssh-client-for-mac)

### 9. **herdr** — Agent-aware multiplexer (как tmux для AI)
- **Платформы:** Linux (Rust binary), в планах macOS
- **Плюсы:** agent-aware (знает, когда claude, codex, devin работают), persistent sessions (как tmux), mouse-управление, panes/splits, notifications (blocked/idle/working), remote over SSH, open source, программный API для агентов
- **Минусы:** Linux-only пока, молодой проект, не полный терминал сам по себе
- **AI:** ✓ специализированный — первый-класс для agents
- **Источники:** [Flavio Copes](https://flaviocopes.com/herdr/), [herdr docs](https://herdr.dev/docs/how-to-work/), [Bitdoze review](https://www.bitdoze.com/herdr-agent-multiplexer/), [Chase AI](https://www.chaseai.io/blog/herdr-terminal-multiplexer-ai-coding-agents)

### 10. **Zed Editor** — IDE с SSH remoting и Terminal Threads
- **Платформы:** macOS, Linux, Windows
- **Плюсы:** SSH remoting (UI локально, code/LSP на сервере), Terminal Threads (Claude/Amp как sidebar), AI-агенты first-class, ControlMaster, auto-reconnect LSP, port forwarding, 2x быстрее чем VS Code, 16x меньше памяти
- **Минусы:** редактор, не терминал; Terminal Threads еще новая фича (май 2026); WASM-расширения не на сервере
- **AI:** ✓ strong — Terminal Threads с Claude Code/Amp
- **Статус:** Zed 1.0 (апрель 2026)
- **Источники:** [Zed remote dev](https://zed.dev/docs/remote-development), [Zed blog](https://zed.dev/blog/remote-development), [Tech Insider](https://tech-insider.org/zed-vs-vscode-2026/)

### 11. **Termix** — новое, быстрое
- **Платформы:** macOS, iOS
- **Плюсы:** пользователи хвалят как «лучшее», быстрый разработчик отзывается на Reddit
- **Минусы:** мало информации, молодое
- **AI:** не ясно
- **Источники:** [App Store](https://apps.apple.com/us/app/termix-ssh-client-terminal/id6739386670)

---

## Ключевые тренды и боли конкурентов

### Архитектура
- **Native** (Ghostty, iTerm2, WezTerm, herdr): <100 МБ, быстро, мало батареи
- **Electron** (Tabby, Wave): 200–400 МБ, медленнее, батарея хуже
- **Hybrid** (Zed: Rust UI + protocol): быстро, масштабируемо, но сложнее

### Боль пользователей (что жаловать в Reviews/Reddit/GitHub)
1. **SSH сессии неживут** на разрыве сети (WezTerm, обычные терминалы) — решение: герdr/Wave/Phosphor §23
2. **Нет AI awareness** (iTerm2, Ghostty, WezTerm) — когда агент работает, терминал не знает → Herdr/Wave/Warp решают
3. **Цена + аккаунт** (Termius $10/мес + обязательный логин) — пользователи уходят
4. **Настройка слишком сложная** (Royal TSX плагины+документы) — жалоба на UX
5. **Экспорт/импорт ломаный** (Termius, Royal) — пользователи хотят контроль
6. **Electron-память** (Tabby, Wave) на слабых ноутбуках → Phosphor: Swift/Rust native
7. **Нет встроенного MCP** (большинство) или неудобный (Warp требует настройки) → Phosphor MCP by default
8. **SSH + terminal раздельно** (iTerm2 = только terminal, SSH отдельно) → Phosphor unified
9. **Нет SFTP в основном** (iTerm2, WezTerm) — только за плагин/панель
10. **Нет team collaboration** (GPUI-на-Rust версии пока) — для future §25

### AI в терминале (2026 состояние)
- **Warp:** agents с full terminal use, /plan, code review, интеграция GitHub Actions
- **Wave:** AI assistant, читает вывод, работает с любым LLM (OpenAI/Claude/Gemini/Ollama)
- **Zed Terminal Threads:** Claude Code/Amp как sidebar-потоки (май 2026)
- **Herdr:** agent-awareness (знает процесс в pane), notifications
- **Остальные:** нет AI

### Keyboard shortcuts (что ценят)
- Command palette (Warp, Zed) — Cmd+K или Ctrl+K
- New tab (iTerm Cmd+T, WezTerm Ctrl+Shift+N) — быстро
- Split panes (iTerm Cmd+D/Cmd+Alt+стрелки, herdr mouse-based)
- Quick connect / SSH hosts list (Termius, Royal, Wave)
- Global hotkey (iTerm, Ghostty) — вызвать из-за приложения

### MCP интеграция (2026)
- **Warp:** native, подключить сервер → typedtools для agents
- **Wave:** готов к MCP (но не явно)
- **Zed:** Terminal Threads + Claude Code (но через IDE, не явный MCP)
- **SSH MCP серверы:** есть (tufantunc-ssh-mcp, mcp-ssh-interactive) но раздельно
- **Phosphor:** встроенный MCP-bridge в плане (§15) — unique selling point

---

## Что взять Phosphor, не ломая идею

Ранжировано по **ценность/усилие** (что дёшево, что ценно):

### 🟢 Вмешиться сразу (мало кода, огромная цена)

1. **Persistent tmux sessions** (§23 READY) — как herdr/WezTerm
   - **Ценность:** сессия выживает разрыв, перезапуск macOS, ноут спит
   - **Усилие:** ✓ уже сделано (SSHInvocation wraps tmux)
   - **Сравнение:** WezTerm требует свой mux, Wave/herdr имеют

2. **Agent-aware status** (§23 READY) — как herdr
   - **Ценность:** рейл показывает "claude working", не "process running"
   - **Усилие:** ✓ уже сделано (process detection в раце)
   - **Пользователь ценит:** "я вижу, что агент не зависнул"

3. **MCP-bridge с политикой** (§15 READY) — как Warp, но лучше
   - **Ценность:** Claude Code работает с твоими серверами, deny-list защита, аудит
   - **Усилие:** ✓ уже сделано (MCPBridge)
   - **Конкурент:** Warp требует настройки, Wave не явно

4. **Mouse-based splits** — как herdr/Ghostty
   - **Ценность:** юзер перетаскивает разделитель, интуитивно
   - **Усилие:** SwiftUI легко (drag gesture на divider)
   - **Сравнение:** WezTerm/Tabby имеют, но iTerm2 нет mouse-split

5. **Global hotkey toggle** (Cmd+Ctrl+P) — как Ghostty/iTerm2
   - **Ценность:** вызвать терминал снизу экрана из другого приложения
   - **Усилие:** macOS Native (NSStatusBar, hotKey binding)
   - **Пользователь ценит:** не переключаться между окнами

6. **SFTP panel** (file browser + drag-drop) — как Tabby/Royal/Wave
   - **Ценность:** скопировать файлы в одном окне, не в отдельном
   - **Усилие:** средне (UI + SSH SFTP channel)
   - **Приоритет:** 2-й план (после §24 бюджет)

7. **Zero-config из коробки** (как Ghostty) — §26 инструкция
   - **Ценность:** "установил → вошел по Touch ID → выбрал сервер → работает"
   - **Усилие:** дизайн UX, уже в плане (§27)
   - **Антипример:** Royal TSX (плагин+документ+свойства = сложно)

8. **Keyboard shortcut customization** (как iTerm2)
   - **Ценность:** power users переделают горячие клавиши под себя
   - **Усилие:** Settings.json + parsing (реализуется постепенно)
   - **Приоритет:** post-1.0

### 🟡 Хорошая идея, но не срочно (требует обсуждения)

9. **Team/shared servers** (§25.3) — как Termius/Royal, но без бэкенда
   - **Ценность:** разные разработчики видят общие серверы, синхронизация ключей
   - **Усилие:** много (HPKE шифрование, версионирование, подписи)
   - **Когда:** Windows/Linux release (§25)
   - **Как:** вариант А (SSH сервер), Б (git), В (файл приглашения)

10. **Health monitoring while detached** (§23) — как herdr
    - **Ценность:** "сессия работает на сервере, видна метрика обновляется"
    - **Усилие:** live metrics каждые N сек (как §11)
    - **Приоритет:** за persistent sessions

11. **Docker health in sidebar** (как наблюдение контейнеров) — расширение §10
    - **Ценность:** quick view: что up, что down, без SSH-в-Docker
    - **Усилие:** парсинг docker stats (уже есть, только UI)
    - **Приоритет:** UI polish

### 🔴 Не делать (пути ошибок конкурентов)

- **Electron.js** — Wave, Tabby платят 300+ МБ, батарея, §24 бюджет
- **Облачная синхронизация** — как Termius ($10/мес), противоречит §2 (client-only)
- **Обязательный аккаунт** — как Termius, пользователи видят как враждебное
- **Сложная настройка** — как Royal TSX (плагин+документ), новичок потеряется
- **Неэкспортируемые данные** — как Termius с ключами, §2 требует freedom

---

## Чего избегать (конкурентные боли)

### Архитектурные ошибки
1. ❌ **SSH session dies on network interruption** (WezTerm, обычный ssh)
   - ✓ Phosphor: tmux живёт на сервере, reconnect автоматический

2. ❌ **Electron overhead** (Tabby 200–400 МБ, медленный)
   - ✓ Phosphor: Swift native macOS, Rust на других системах

3. ❌ **Cloud-dependent** (Termius $10/мес, разлука с ключами)
   - ✓ Phosphor: §2 client-only, всё на диске юзера, экспорт свободен

4. ❌ **No agent awareness** (iTerm2, Ghostty не знают про Claude/Codex)
   - ✓ Phosphor: §23 детект процесса, herdr-style status

### UX ошибки
5. ❌ **Mandatory account** (Termius login required)
   - ✓ Phosphor: не нужна регистрация, профиль на диске

6. ❌ **Complex setup** (Royal TSX: плагин → документ → свойства)
   - ✓ Phosphor: §26–27 "zero-config" инструкция, главный путь без книги

7. ❌ **Confusing export** (Termius "complicated", Royal документы)
   - ✓ Phosphor: §8.6 `phosphor export` → .zip с JSON, читаемо

8. ❌ **SSH + Terminal separate** (iTerm2 = терминал, SSH отдельно ищи)
   - ✓ Phosphor: unified, одна вкладка "SSH", другая "Local"

### Функциональные упущения
9. ❌ **No SFTP in main view** (iTerm2, WezTerm только если плагин)
   - ✓ Phosphor: §10 Docker-like view, можно SFTP панель добавить

10. ❌ **SSH over broken connection** (обычный ssh теряет сессию)
    - ✓ Phosphor: ControlMaster SSH + tmux = живой процесс на сервере

11. ❌ **AI not integrated** (большинство: терминал + отдельно AI инструмент)
    - ✓ Phosphor: §15 MCP-bridge встроен, Claude Code работает с хостами

12. ❌ **Unlimited buffers** (скроллбэк жрёт память)
    - ✓ Phosphor: §24 кольцевые буферы, лимиты, контроль батареи

13. ❌ **No multiplexing awareness** (терминал не знает про tmux статус)
    - ✓ Phosphor: §23 парсит `tmux list-sessions`, показывает status

14. ❌ **Team collaboration late/absent** (Termius это фишка, остальные нет)
    - ✓ Phosphor: §25 teams в плане (без бэкенда, HPKE шифрование)

---

## Резюме: Позиция Phosphor на рынке

| Фактор | Положение |
|--------|----------|
| **Архитектура** | Native Swift (macOS) → Rust GPUI (cross-platform), не Electron ✓ |
| **SSH + Terminal** | Unified первый день ✓ |
| **Persistent sessions** | Встроены с tmux, herdr-style ✓ |
| **Agent-aware** | Да, herdr-style process detection ✓ |
| **MCP-bridge** | Встроен, с политикой, уникально ✓ |
| **Teams** | В плане (§25), без бэкенда ✓ |
| **Цена** | Free, no subscription needed ✓ |
| **Account** | Не нужен ✓ |
| **Export** | JSON, полный контроль ✓ |
| **Memory** | <150 МБ (§24), контролируется в CI ✓ |
| **AI** | Своя MCP, не зависит от третьих ✓ |

**Главное отличие:** Phosphor = **терминал для AI агентов** (MCP first, agent-aware tmux, durable SSH) + командная кроссплатформа (потом), а конкуренты либо **terminal-first** (iTerm/Ghostty), либо **SSH-first** (Termius), либо **AI-first но Electron** (Warp/Wave).

---

## Источники

### Termius
- [Capterra reviews](https://www.capterra.com/p/234457/Termius/reviews/)
- [FindStack](https://findstack.com/products/termius/reviews)
- [MakerStack review](https://makerstack.co/reviews/termius-review/)

### Warp
- [Help Net Security](https://www.helpnetsecurity.com/2026/04/30/warp-open-source-client/)
- [Warp GitHub](https://github.com/warpdotdev/warp)
- [Warp docs 2026](https://docs.warp.dev/changelog/2026/)
- [Warp AI Tutorial](https://www.devshelfhub.com/articles/warp-ai-coding-tutorial-2026/)

### iTerm2
- [Features](https://iterm2.com/features.html)
- [ShortcutRef](https://shortcutref.com/en/iterm2/)

### Ghostty
- [Ghostty.org](https://ghostty.org/)
- [GitHub](https://github.com/ghostty-org)
- [Petronella Tech guide](https://petronellatech.com/blog/ghostty-terminal-emulator-setup-configuration-guide-2026/)

### WezTerm
- [SSH docs](https://wezterm.org/ssh.html)
- [Multiplexing](https://wezterm.org/multiplexing.html)
- [mwop.net howto](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html)

### Tabby
- [MakerStack review](https://makerstack.co/reviews/tabby-terminal-review/)
- [Termique comparison](https://termique.app/vs/tabby/)
- [X-CMD](https://www.x-cmd.com/install/tabby/)

### Wave Terminal
- [OpenReplay comparison](https://blog.openreplay.com/warp-wave-terminal-ai-powered/)
- [Wave Terminal](https://www.waveterm.dev/)
- [Stork.AI review](https://www.stork.ai/en/wave-terminal)

### Royal TSX
- [Features](https://royalapps.com/ts/mac/features)
- [Conduit comparison](https://www.conduitdesktop.com/blog/best-ssh-clients-for-mac)
- [SSHive guide](https://sshive.app/en/best-ssh-client-for-mac)

### herdr
- [Flavio Copes deep dive](https://flaviocopes.com/herdr/)
- [herdr docs](https://herdr.dev/docs/how-to-work/)
- [Bitdoze review](https://www.bitdoze.com/herdr-agent-multiplexer/)
- [Chase AI](https://www.chaseai.io/blog/herdr-terminal-multiplexer-ai-coding-agents)

### Zed
- [Remote development](https://zed.dev/docs/remote-development)
- [Zed blog announcement](https://zed.dev/blog/remote-development)
- [Tech Insider comparison](https://tech-insider.org/zed-vs-vscode-2026/)

### Terminal comparison & architecture
- [DEV Community Linux terminals 2026](https://dev.to/shrsv/state-of-linux-terminal-emulators-in-2026-1gh5)
- [NexaSphere comparison](https://nexasphere.io/blog/best-terminal-emulators-developers-2026)
- [Scopir comparison](https://scopir.com/posts/best-terminal-emulators-developers-2026/)

### MCP
- [Model Context Protocol spec](https://modelcontextprotocol.io/specification/2026-07-28)
- [LobeHub SSH MCP](https://lobehub.com/mcp/tufantunc-ssh-mcp)
- [GitHub mcp-ssh](https://github.com/aiondadotcom/mcp-ssh)
- [GitHub ssh-mcp](https://github.com/tufantunc/ssh-mcp)
- [GitHub mcp-ssh-interactive](https://github.com/qnxqnxqnx/mcp-ssh-interactive)
