# Phosphor: Keyboard Shortcuts Inventory & Proposal

**Date:** 2026-09-24  
**Task:** Inventory existing shortcuts, propose full keymap, sketch implementation  
**Status:** Read-only analysis

---

## 1. Existing Shortcuts (Current State)

Only **one** keyboard shortcut is implemented in the codebase:

| File | Line | Action | Shortcut | Scope |
|------|------|--------|----------|-------|
| `PhosphorUI/RootView.swift` | ~290 | Section (tab) selection | ⌘1…⌘9 | Global, main window |

**Evidence:** `grep -r keyboardShortcut` returns only one match.

### What Exists but Has No Shortcut

**Terminal operations** (from `AppModel+Sessions.swift`):
- `splitTerminal()` — split pane
- `attachSession(_ name: String)` — attach to tmux session
- `killLocalSession(_ name: String)` — close session
- `focusLocal(_ name: String?)` — switch pane focus
- `createLocalSession()` — new session

**Host/Connection** (from `AppModel.swift`):
- `connect(to host: ServerHost)` — establish SSH
- `disconnect()` — close connection
- `lock()` / `unlock()` — authentication
- Menu items: add host, edit host, delete host

**File operations** (implied in `HostsView`, `FilesView`):
- Find / search
- Upload / download
- New folder

**Settings** (from `ThemeView`, `RootView`):
- Zoom in/out (font size)
- Theme switch
- Appearance settings

---

## 2. Conflict Analysis

### Keys That Must Pass Through to Terminal

These must **not** be intercepted by the app — they go to the running shell:

| Pattern | Why | Action |
|---------|-----|--------|
| `Ctrl-C` | Interrupt signal | **Must pass through** |
| `Ctrl-D` | EOF, logout | **Must pass through** |
| `Ctrl-Z` | Suspend | **Must pass through** |
| `Ctrl-S` / `Ctrl-Q` | Flow control (rare but used) | **Pass through if tmux off** |
| `Ctrl-A` | Line start (bash default) | **Pass through** |
| `Ctrl-E` | Line end | **Pass through** |
| `Cmd-C` / `Cmd-V` | macOS copy/paste | **Intercepted by app** (term sees Ctrl-C) |

### tmux Key Prefix Conflict

If user enables `permanent sessions` (§23 of PLAN), `Ctrl-B` (default tmux prefix) is bound server-side, not client. **No conflict** — user types `Ctrl-B` → SSH → tmux on server sees it.

### macOS System Reserved Keys

| Key | System Use | Conflict? |
|-----|-----------|-----------|
| ⌘-Space | Spotlight | **Conflict possible** — use Alt instead or ⇧⌘P |
| ⌘-Tab | App switcher | **Never override** |
| ⌘-, | Preferences (convention) | **No conflict** (we control our prefs) |
| ⌘-Q | Quit (convention) | **Conflict** — should we support it? |
| ⌘-W | Close window (convention) | **Conflict** — could close current pane |
| ⌃⌘F | Full screen (convention) | **No conflict** |

---

## 3. Proposed Keymap

Based on conventions from **iTerm2**, **Terminal.app**, **Ghostty**, **Warp**, **Termius**.

### 3.1 Core Navigation (No conflicts)

| Action | Shortcut | Rationale | Competitors |
|--------|----------|-----------|-----------|
| Go to Hosts | ⌘1 | Already exists ✓ | iTerm2: N/A |
| Go to Terminal | ⌘2 | Already exists ✓ | — |
| Go to Files | ⌘3–⌘8 | Already exists ✓ | — |
| Switch section left/right | ⌘← / ⌘→ | macOS convention for tabs | Terminal.app: N/A |
| Command palette | ⌘K | **OPTION 1** (see 3.6) | VS Code, Warp |
| Command palette | ⇧⌘P | **OPTION 2** (alternative) | Sublime, VSCode |

### 3.2 Terminal Pane Operations

Terminal tab only. Must allow pass-through to shell when terminal is focused.

| Action | Shortcut | Rationale | Competitors |
|--------|----------|-----------|-----------|
| **New session** | ⌘T | Standard: new tab | iTerm2, Terminal.app, Ghostty |
| **New pane (split vertically)** | ⌘D | Standard: divide | iTerm2, Terminal.app |
| **New pane (split horizontally)** | ⇧⌘D | Extension: shift for ortho | iTerm2 (⌘-Alt-I) |
| **Focus pane: up** | ⌘↑ (or ⌥⌘↑) | Mnemonic | iTerm2: ⌘-Alt-Up |
| **Focus pane: down** | ⌘↓ | — | iTerm2: ⌘-Alt-Down |
| **Focus pane: left** | ⌘← | — | iTerm2: ⌘-Alt-Left |
| **Focus pane: right** | ⌘→ | — | iTerm2: ⌘-Alt-Right |
| **Focus next pane** | ⌘] | Alternative (cycle) | iTerm2: ⌘-] |
| **Focus prev pane** | ⌘[ | — | iTerm2: ⌘-[ |
| **Close pane** | ⌘W | macOS close convention | Terminal.app |
| **Kill session** | ⇧⌘W | Extended: shift for stronger | — |
| **Zoom pane to fullscreen** | ⌘Z | Mnemonic | iTerm2: ⌘-Z |
| **Zoom out (restore)** | ⌘Z again | Toggle | — |

**Resolution:** ⌘← and ⌘→ **conflict with section navigation**. Options:
- **A**: Use section nav only, disable pane focus (users press ⌥⌘ instead)
- **B**: Make ⌘← / ⌘→ context-sensitive: in Terminal, focus pane; elsewhere, change section
- **C**: Change section nav to ⌘[ / ⌘] and free ⌘← / ⌘→ for panes

**Recommendation:** Option C — use ⌘[ / ⌘] for section, ⌘← / ⌘→ for pane focus. **Or** make Tab aware: if Terminal is focused, arrows = panes; else = sections. The second is better UX.

---

### 3.3 Host Management

| Action | Shortcut | Rationale | Competitors |
|--------|----------|-----------|-----------|
| **Quick connect** | ⌘/ (slash) | Search hosts | Warp, Termius |
| **Connect to host** | ⌘⏎ (Enter) | In search field | — |
| **Edit host** | ⌘E | Mnemonic | — |
| **Delete host** | ⌘Delete | Mnemonic | — |
| **New host** | ⌘N | macOS convention | Termius |
| **New group** | ⌘⇧N | Extension: shift for group | — |
| **Search hosts** | ⌘F | macOS find | Terminal.app, Ghostty |

---

### 3.4 File Operations

Files tab only.

| Action | Shortcut | Rationale | Competitors |
|--------|----------|-----------|-----------|
| **Find / filter files** | ⌘F | macOS convention | Finder |
| **Upload file** | ⌘U | Mnemonic | — |
| **Download file** | ⌘S | macOS save (alt: Cmd-Shift-S) | — |
| **New folder** | ⌘⇧N | macOS convention | Finder |
| **Delete file** | ⌘Delete | macOS convention | Finder |
| **Rename** | ⌘R | Mnemonic | — |

---

### 3.5 Settings & Window

| Action | Shortcut | Rationale | Competitors |
|--------|----------|-----------|-----------|
| **Settings / Preferences** | ⌘, (comma) | macOS convention | Universal |
| **Lock app** | ⌃⌘L | Mnemonic + Mac convention | Ghostty, others |
| **Zoom in (font)** | ⌘+ | macOS standard | All |
| **Zoom out (font)** | ⌘- | — | All |
| **Reset zoom** | ⌘0 | — | All |
| **Toggle full screen** | ⌃⌘F | macOS convention | Universal |
| **Toggle pet** | ⌘. (period) | Easter egg | — |
| **Clear terminal** | ⌘K (conflict!) | Standard: clears scrollback | iTerm2, Terminal.app, Ghostty |

**Conflict:** ⌘K for both command palette and clear. **Resolution:** See 3.6.

---

### 3.6 Command Palette: Design Fork

Two design options with trade-offs:

#### Option A: ⌘K = Clear Terminal (Standard)
- **Pros:** Matches iTerm2/Terminal.app/Ghostty convention. Users expect it. No confusion.
- **Cons:** No command palette. All features must be in menus or explicit shortcuts.
- **When to use:** If app philosophy is "menus, not search." Matches Phosphor's design (explicit, minimal UI).

#### Option B: ⌘K = Command Palette
- **Pros:** Discoverability. User doesn't need to remember all shortcuts. Modern UX (VS Code, Warp).
- **Cons:** Conflicts with terminal standard. Users will try ⌘K to clear and be surprised.
- **When to use:** If planning many features and want power-user experience.

#### Option C: ⇧⌘P = Command Palette (Unique)
- **Pros:** No conflict with clear. Still discoverable (right next to ⌘P for print, not relevant here).
- **Cons:** Less standard on macOS. Users expect ⌘K.

**Recommendation:** **Option A** — define clear as ⌘K, **no command palette** in v1. Keep app explicit. Users can access features via menu bar + discoverable shortcuts.

---

## 4. Full Recommended Keymap

### Terminal Tab (Priority 1: Implement First)

```
⌘T           New session / tab
⌘D           Split vertically
⇧⌘D          Split horizontally
⌘W           Close pane
⇧⌘W          Kill session (stronger)
⌘↑ ⌘↓ ⌘← ⌘→  Focus pane (up/down/left/right)
⌘]           Focus next pane (alternative)
⌘[           Focus previous pane (alternative)
⌘K           Clear terminal (scrollback)
⌘Z           Zoom pane fullscreen / restore
```

### Hosts Section (Priority 2)

```
⌘/           Quick connect / search
⌘N           New host
⌘⇧N          New group
⌘E           Edit selected host
⌘Delete      Delete selected host
```

### Global / Any Section

```
⌘1 … ⌘9      Go to section [existing]
⌘←  ⌘→       Previous / next section (if not in terminal)
⌘F           Find (context-sensitive: hosts, files, terminal text)
⌘,           Settings / Preferences
⌃⌘L          Lock app
⌘+           Zoom in (font)
⌘-           Zoom out (font)
⌘0           Reset zoom
⌃⌘F          Toggle fullscreen
⌘.           Toggle pet (easter egg)
```

### Files Tab (Lower Priority)

```
⌘F           Filter files
⌘U           Upload
⌘S           Download
⌘⇧N          New folder
⌘Delete      Delete file
⌘R           Rename
```

---

## 5. Implementation Sketch

### 5.1 Where in Code

**SwiftUI Approach (Recommended):**
- Add `.keyboardShortcut()` modifiers to buttons in each view
- `RootView.swift`: Wrap section navigation to make context-aware (Terminal vs. other)
- `TerminalView.swift`: Add pane navigation + split shortcuts
- `HostsView.swift`: Add host action shortcuts
- `FilesView.swift`: Add file action shortcuts

**Centralized Command Handler (Optional, for consistency):**
Create `KeyboardShortcutHandler.swift`:
```swift
@MainActor
struct KeyboardShortcutHandler {
    let model: AppModel
    
    func handleShortcut(_ key: KeyboardShortcut) async {
        switch (key.modifiers, key.character) {
        case (.command, "t"):
            model.createLocalSession()
        case (.command, "d"):
            model.splitTerminal()
        // ... etc
        }
    }
}
```
Attach to root view via `.onKeyDown { }` or `.commands`.

### 5.2 Making Shortcuts Discoverable

1. **Menu Bar Items** (NSMenu): Add macOS-standard File/Edit/View menus with shortcut hints visible
2. **Tooltip Hints**: Hover over buttons → show shortcut (e.g., "New Session (⌘T)")
3. **Cheat Sheet**: Keyboard shortcut: **⌘?** opens a modal with full keymap (design: 2–4 columns, organized by section)
4. **In-App Hints**: First-run tip: "Tip: Press ⌘T for new session"

### 5.3 Localization

All shortcuts themselves are language-independent (symbols), but **labels must be localized**.

**Strategy:**
- Keep shortcut display as UTF-8 symbols: `⌘T`, `⇧⌘D`, etc. (locale-independent)
- Localize **action names** in `Localizable.xcstrings`:
  ```json
  "shortcut.newSession": {
    "en": "New Session",
    "ru": "Новая сессия"
  }
  ```
- In menu bar and tooltips, show: `"Новая сессия (⌘T)"`

### 5.4 User Rebinding: Worth It?

**Project rule:** "No 'for the future' work" (CLAUDE.md). Rebinding requires:
- Preferences UI for keybinds (~50–100 lines)
- Conflict detection (~30 lines)
- Persistence (~20 lines)
- **Total:** ~200 lines, non-trivial testing

**Recommendation:** **Skip in v1**. Add only if user asks. Revisit after first release and gather feedback.

---

## 6. Additional Considerations

### Multi-Pane Navigation Ambiguity

If 4 panes are open, which does ⌘↑ focus?
- **Option 1:** Geometric — up in visual grid (hard to predict)
- **Option 2:** Cycle order — tmux/screen style: focus next in creation order
- **Recommendation:** Option 2, **plus visual feedback** (highlight focused pane border) so user learns the order

### Paste Behavior (Cmd-V vs. Terminal Paste)

macOS paste is `⌘V`, but in terminal pane, should it:
1. Paste to terminal (common: just type the text into stdin)
2. Paste to search box (if searching)

**Recommendation:** Make it context-aware. When terminal pane is focused, ⌘V goes to term. When search is active, ⌘V goes to search.

### Accessibility

Users with limited dexterity may struggle with ⌘⇧ combos. Provide:
- Tooltips showing **alternative spellings**: "⌘D or ⌘⇧D"
- Customizable accessibility shortcuts (future)

---

## 7. Rollout Plan

1. **Phase 1 (MVP):** Terminal pane only (⌘T, ⌘D, ⇧⌘D, ⌘W, ⌘K, ⌘↑↓←→)
2. **Phase 2:** Host section (⌘N, ⌘E, ⌘Delete, ⌘/)
3. **Phase 3:** Global (⌘,, ⌃⌘L, ⌘+/-, ⌃⌘F)
4. **Phase 4 (Polish):** Files, cheat sheet (⌘?), tooltips

---

## Appendix A: Competitor Analysis

### iTerm2
- New tab: ⌘T ✓
- New split: ⌘D (vert), ⌘⌥I (horiz)
- Focus split: ⌘⌥← / → / ↑ / ↓
- Clear: ⌘K ✓
- Settings: ⌘,

### Terminal.app
- New tab: ⌘T ✓
- New window: ⌘N
- Close: ⌘W ✓
- Settings: Terminal > Preferences
- Find: ⌘F ✓
- Clear: ⌘K ✓

### Ghostty
- New tab: ⌘T ✓
- Split: ⌘D (vert), ⌘⇧D (horiz) ✓
- Focus: ⌘← / → / ↑ / ↓
- Clear: ⌘K ✓
- Zoom: ⌘+ / - ✓

### Warp
- Command palette: ⌘K (but also clears!)
- Quick connect: ⌘/
- Settings: ⌘,

### Termius
- Quick connect: ⌘/
- New tab/group: ⌘N / ⌘⇧N
- Settings: Menu > Preferences

---

## Appendix B: Files Affected

To implement:

1. **PhosphorUI/RootView.swift** — Modify section navigation (⌘1-9 → context-aware ⌘← / →)
2. **PhosphorUI/TerminalView.swift** — Add shortcuts (⌘T, ⌘D, ⇧⌘D, ⌘W, ⌘↑↓←→, ⌘K, ⌘Z)
3. **PhosphorUI/HostsView.swift** — Add shortcuts (⌘N, ⌘⇧N, ⌘E, ⌘Delete, ⌘/)
4. **PhosphorUI/FilesView.swift** — Add shortcuts (⌘F, ⌘U, ⌘S, ⌘⇧N, ⌘Delete, ⌘R)
5. **PhosphorUI/AppModel+Sessions.swift** — Ensure actions are wired
6. **PhosphorUI/Localizable.xcstrings** — Add all action labels (ru + en)
7. **NEW: PhosphorUI/KeyboardShortcuts.swift** — Optional: centralized handler

---

## Conclusion

**Start with Option A** (no command palette, ⌘K = clear). Implement terminal pane shortcuts first (⌘T/D/W/K/arrows). Add host & file shortcuts next. Defer rebinding & cheat sheet to v2.

The minimal viable keymap covers 80% of user workflows (new session, split, navigate panes, clear, lock) in ~15 shortcuts — easy to learn, hard to forget.
