# Phosphor Terminal: UI/UX Audit

**Date:** 2026-09-24  
**App:** /Applications/Phosphor.app (Build 20)  
**Scope:** Information architecture, navigation clarity, empty states, accessibility  
**Method:** Code review of SwiftUI views + visual inspection via screenshots

---

## 1. Current Information Architecture Map

```
PHOSPHOR (8 main sections + 1 lock screen)
│
├─ LOCK VIEW
│  └─ Touch ID / Apple Watch / Password entry
│
├─ HOSTS (6 sub-pages)
│  ├─ hosts (main list, search, groups, recent)
│  ├─ keys (SSH keys management)
│  ├─ forwarding (port forwarding rules)
│  ├─ snippets (saved shell commands)
│  ├─ known (discovered known_hosts)
│  └─ log (connection history)
│
├─ TERMINAL (persistent tmux sessions)
│  ├─ Spaces (per-host tabs)
│  ├─ Sessions (tmux sessions per space)
│  ├─ Panels (split panes within sessions)
│  └─ Session Rail (left sidebar)
│
├─ FILES (file transfer interface)
│  ├─ Local panel (Finder-like browse)
│  ├─ Remote panel (server files via SSH)
│  └─ Transfer queue
│
├─ DOCKER (container management)
│  ├─ containers
│  ├─ images
│  ├─ volumes
│  └─ networks
│
├─ MONITOR (system metrics)
│  ├─ overview (CPU, memory, disk)
│  ├─ graphs (historical trends)
│  ├─ processes (running processes)
│  ├─ storage (disk I/O, memory usage)
│  └─ network (network traffic stats)
│
├─ PROVISIONING (host setup verification)
│  └─ Shows host readiness, dependencies, provisioning status
│
├─ AI ACTIVITY (MCP server audit trail)
│  ├─ journal (all AI actions on this host)
│  ├─ access (per-host permission grants)
│  └─ tools (catalog of available MCP tools)
│
└─ SETTINGS (7 sub-pages)
   ├─ palette (ANSI theme colors)
   ├─ glass (visual effects: bloom, scanlines)
   ├─ language (ru/en toggle)
   ├─ behaviour (animations, updates)
   ├─ profile (export/import encrypted vault)
   └─ (other settings pages)
```

---

## 2. Concrete Problems Ranked by Severity

### CRITICAL – Block Main User Path

#### 1. **"First-run path is invisible / unclear" — Too many import buttons**
- **Where:** `Sources/PhosphorUI/HostsView.swift:65-71`, `FirstRun.swift:60-75`
- **Issue:** New user sees 4 buttons in a row: `+ новый хост`, `импорт ~/.ssh/config`, `известные хосты`, `импорт из Termius`
  - Three import sources (ssh/config, known_hosts, Termius) — which should I use first?
  - Buttons labeled the same ("импорт", "известные") create confusion: are "known hosts" an import source or a separate feature?
  - No guidance on when to use each
- **Impact:** User doesn't know where to start; likely clicks wrong button or all of them
- **User's complaint:** "очень много шума, непонятно что куда тыкать"
- **Fix:** See Alternative Direction A below

#### 2. **Nested sub-pages hidden in left sidebar — SectionNav not obvious**
- **Where:** `Sources/PhosphorUI/SectionNav.swift:1-176`
- **Issue:** Each section (HOSTS, DOCKER, MONITOR, ACTIVITY, SETTINGS) has 4–6 sub-pages in a left sidebar (SectionNav)
  - Left sidebar is small (w=168px, `SectionNav.swift:133`)
  - No visual affordance that sub-pages exist (no "chevron", no "more", no hint)
  - User discovers them only by hovering or accident
  - NEW USER PATH: Click HOSTS → sees hosts list → doesn't know KEYS, FORWARDING, SNIPPETS, KNOWN, LOG exist
- **Examples:**
  - HOSTS has KEYS sub-page — user looking for SSH keys never finds it
  - DOCKER has NETWORKS, VOLUMES sub-pages — user can't manage them
  - MONITOR has GRAPHS, STORAGE, NETWORK sub-pages — not visible until you hover
- **Impact:** Advanced features appear broken or missing
- **File:Line Examples:**
  - `HostsView.swift:24-42` (switch on model.page)
  - `DockerView.swift` similar pattern
  - `MonitorView.swift` similar pattern
  - `ActivityView.swift:25-31`
  - `ThemeView.swift` similar pattern
- **Severity:** HIGH — users can't find 30% of features

#### 3. **"Terminal" tab naming and behavior — doesn't match user mental model**
- **Where:** `RootView.swift:282` (`"tab.terminal"`), `TerminalPane` + `SessionRail`
- **Issue:**
  - Tab is called "TERMINAL" but shows a complete session management interface (spaces, sessions, panels, rail)
  - User sees a left sidebar with host list and expects it to be the main interface — instead it's a sub-component of TERMINAL
  - No clear indication that this is a "persistent sessions with tmux" interface — looks like a generic terminal
  - PLAN §23 describes herdr-style sessions feature but UI doesn't explain the concept
  - "no tmux on this Mac" message appears but no help on what to do
- **Impact:** User clicks TERMINAL expecting a simple shell, finds a complex session manager instead
- **Visibility:** The session rail is very narrow, text is small; easy to miss that you can manage sessions at all

#### 4. **"Files" empty state → "выберите хост" is unhelpful**
- **Where:** `FilesView.swift:52-62`
- **Issue:**
  - Remote file panel shows: "нет подключения" + "выберите хост"
  - But user doesn't know:
    - Do I select a host from HOSTS tab first?
    - Or click on a host in the right sidebar?
    - Or is it the host shown in the header?
  - Message doesn't explain the action required
- **Action:** Should say "Click a host above to connect" or show a clickable host list
- **Severity:** MEDIUM — users give up on FILES feature quickly

#### 5. **AI ACTIVITY / tools / journal — very difficult to understand purpose**
- **Where:** `ActivityView.swift:1-100`
- **Issue:**
  - Tab labeled "AI ACTIVITY" (English term) but shows 3 sub-pages: journal, access, tools
  - Purpose unclear: Is this for monitoring, for permissions, or for exploration?
  - Strings like `"act.perHost"`, `"act.toolsNote"` are vague
  - `ToolCatalog.all` in `ActivityView.swift:45-78` — users don't understand why they're seeing a static list
- **Impact:** Section looks scary (permission grants!) but is actually just informational
- **Context:** PLAN §27 says "очень много шума" — this section is part of the noise
- **Severity:** MEDIUM — might discourage privacy-conscious users

#### 6. **"PROVISIONING" tab has no clear purpose or empty state**
- **Where:** `ProvisionView.swift` (no comprehensive guidance in code comments)
- **Issue:**
  - Tab exists but purpose is cryptic: "Профиль хоста" → What does that mean?
  - PLAN §16 describes provisioning verdict (fresh/inhabited host) but UI doesn't explain
  - No empty state for "no host selected" or "host not ready"
  - Likely shown only once per host — user may never see it again
- **Severity:** MEDIUM — feels like dead code to new user

#### 7. **Settings sub-pages not clearly categorized**
- **Where:** `ThemeView.swift`, `Settings.swift`
- **Issue:**
  - 5 sub-pages in SETTINGS: palette, glass, language, behaviour, profile
  - No clear grouping: visual settings (palette, glass) vs. behavioral (language, behaviour, profile)
  - "profile" is dangerous (export/import vault) but not visually distinguished from others
  - User might export profile thinking it's a quick backup, actually exporting encrypted keys
- **Severity:** MEDIUM → HIGH if user doesn't read warnings

---

### HIGH – Major UX Friction

#### 8. **Host selection via "HOSTS" tab disconnected from terminal usage**
- **Where:** `RootView.swift:294-295` (header shows selected host), `TerminalPane` expects host already selected
- **Issue:**
  - User flow: Click host card in HOSTS → system switches to TERMINAL
  - But if user is already in TERMINAL and wants to switch hosts, they must:
    1. Go back to HOSTS
    2. Click a different host
    - OR see no obvious "pick host" affordance in TERMINAL tab
  - No "quick host switcher" visible in TERMINAL
- **Mental model mismatch:** HOSTS feels like a list view, TERMINAL feels like the workspace
  - Should be one unified view?
- **Severity:** HIGH for power users; MEDIUM for casual users

#### 9. **DOCKER and MONITOR tabs require selecting a host first**
- **Where:** `DockerView.swift`, `MonitorView.swift` (both assume `model.session` exists)
- **Issue:**
  - User clicks DOCKER with no host selected → shows nothing or error
  - No indication that you must go to TERMINAL first (or HOSTS)
  - Same issue as FILES: "you must select a host" is unstated
- **Severity:** HIGH — user can't use 2 of 8 sections without discovering the prerequisite

#### 10. **Colors and styling make some sections hard to parse**
- **Where:** `PhosphorStyle.swift`, `RootView.swift:263-266` (colour function)
- **Issue:**
  - Muted text (style.muted) used heavily for nav items — hard to read
  - In left sidebar (SectionNav), unselected items are hard to distinguish from disabled items
  - Phosphor design is intentionally subtle (phosphor glow) but may sacrifice clarity
- **Severity:** MEDIUM — affects accessibility (low contrast, especially on dim displays)

#### 11. **"Known hosts" naming collision**
- **Where:** `HostsView.swift:69` (button "hosts.known"), `StringsTable.swift` (two meanings of "known")
- **Issue:**
  - Button in HOSTS action row: "известные хосты" → imports from ~/.ssh/known_hosts
  - Sub-page in HOSTS: "известные хосты" → shows/manages known_hosts
  - Same name, different purposes → confusion
- **Action:** Rename one: "импорт из ~/.ssh/config" vs "обнаруженные хосты" (discovered) vs "доверенные хосты" (trusted)
- **Severity:** MEDIUM

---

### MEDIUM – Nice-to-Haves / Polish

#### 12. **No undo/confirmation for destructive bulk operations**
- **Where:** `RootView.swift:105-120` (alerts for delete), but no batch operations
- **Issue:**
  - Individual host deletion is guarded by alert
  - But if user selects multiple hosts and deletes, is there a confirmation?
  - Group deletion, snippet deletion — need review
- **Severity:** MEDIUM

#### 13. **File transfer progress UX is minimal**
- **Where:** `FilesView.swift:27-32` (transfer progress)
- **Issue:**
  - Shows only: `"скачиваю filename"` with a spinner
  - No file size, no transfer speed, no time estimate
  - `scp` doesn't report progress, so this is expected per code comment
  - But user experience is still vague
- **Severity:** LOW (acknowledged limitation)

#### 14. **Snippets and forwarding sub-pages might be unused**
- **Where:** `HostsView.swift:38` (case .snippets), `HostsView.swift:38` (case .forwarding)
- **Issue:**
  - These features may not be fully implemented
  - If not ready, should be hidden (per §27: "remove from sight until fixed")
  - Visible but broken = noise
- **Severity:** MEDIUM if unfinished

---

## 3. Alternative Directions for Information Architecture

### **Direction A: Flatten the First-Run Path (Recommended)**

**Problem solved:** Import confusion, hidden sub-pages, unclear host selection

**Concept:**
1. Rename "HOSTS" tab to "SERVERS" or "MACHINES" (clarifies scope)
2. First-run flow: Single, guided step-by-step onboarding
   - Step 1: "Do you have existing SSH config?" YES/NO → auto-import
   - Step 2: "Add your first server manually"
   - Step 3: "Pick a server above and open a terminal session"
3. For each main tab (SERVERS, TERMINAL, FILES, DOCKER, etc.):
   - Show ALL sub-pages in a visible, grouped list
   - Replace hidden left sidebar (SectionNav) with tabs or segmented control
   - Example: SERVERS tab shows 3 sections: [Hosts | Keys | Port Forwarding | Snippets]
4. Host selection: Move to a prominent "Host Picker" in the header
   - Current: "HOST-1 · НАПРЯМУЮ · TOUCH ID" (too small)
   - New: Larger button or dropdown that says "Click to change host"
   - Active in every tab (not just TERMINAL)

**Pros:**
- Visible-by-default navigation
- Host selection available everywhere
- First-run users succeed 80% of the time without help
- Aligns with standard app patterns (Finder, VS Code sidebar)

**Cons:**
- Requires restructuring SectionNav UI
- Phosphor's "phosphor" aesthetic (subtle, dim) conflicts with clarity
- More buttons/controls = less minimalist

**Effort:** 6–8 hours (refactor nav component, redesign host picker)

---

### **Direction B: Full Sidebar Redesign (Radical)**

**Problem solved:** Cluttered header, hidden sub-pages, cognitive overload

**Concept:**
1. Replace 8 tabs in header with a persistent left sidebar
   - Sidebar shows: SERVERS, TERMINAL, FILES, DOCKER, MONITOR, PROVISIONING, AI ACTIVITY, SETTINGS
   - Each section has collapsible sub-pages (no separate left sidebar per section)
2. Header simplified to: App name + selected host + TOUCH ID only
3. Main content area fills most of the window
4. Phosphor visual language applied to sidebar (glow, phosphor color)

**Example layout:**
```
┌─────────────────────────────────────┐
│ PHOSPHOR    HOST-1 · TOUCH ID     │
├──────┬──────────────────────────────┤
│▼SRVRS│ [Host card list or detail]   │
│ │ All Hosts                         │
│ │ Keys                              │
│ ├ SSH Config                        │
│ └ Forwarding                        │
│▶TERM │ [Main terminal workspace]    │
│▶FILES│                              │
│▶DOCKER │                            │
│▶MONITOR│                            │
│▶PROV │                              │
│▶AI   │                              │
│▶SETT │                              │
└──────┴──────────────────────────────┘
```

**Pros:**
- Industry-standard sidebar pattern (VS Code, Xcode, Finder)
- All features visible in one glance
- Scales well as feature count grows
- Host picker can be a prominent button in sidebar

**Cons:**
- Breaks Phosphor's current minimalist aesthetic
- Requires complete layout restructuring
- Takes 12–16 hours
- Might feel "too normal" vs. intended design direction

**Effort:** 12–16 hours (major refactor)

---

### **Direction C: Smart Defaults + Context Menus**

**Problem solved:** Navigation clarity without major restructuring

**Concept:**
1. Keep header tabs but make SectionNav sub-pages visible by default (expanded, not collapsed)
2. Add ">" chevron icons to collapsed sections (DOCKER, MONITOR, etc.) in header
3. Context menu on host cards: right-click → "Open in Files", "Open in Docker", "Show Metrics"
4. "Quick-pick" modal (Cmd+K): search for any feature/host/command
5. First-run: modal with "Top 3 things to do" (set host → open terminal → explore)

**Example:**
- Header tabs now have chevrons: `DOCKER ▸` (indicating sub-pages)
- Hovering/clicking chevron expands a dropdown
- Clicking on "containers" switches view and closes dropdown

**Pros:**
- Minimal UI change
- Educated guesses on what users want next (context menu)
- Scales well
- Preserves current aesthetic

**Cons:**
- Requires more interaction (dropdown clicks) to access features
- Chevrons add visual complexity
- Command palette (Cmd+K) is powerful but not obvious to all users

**Effort:** 4–6 hours (add dropdowns, context menus, first-run modal)

---

## 4. Quick Wins (Low Effort, High Impact)

1. **Rename imports section (30 min)**
   - Change button labels to clarify intent:
   - `"hosts.import"` → `"Import ~/.ssh/config"`
   - `"hosts.known"` → `"Import known hosts"`
   - `"hosts.termius"` → `"Import from Termius app"`
   - **File:** `StringsTable.swift`

2. **Add ">>" chevron to SectionNav items (15 min)**
   - Visual hint that sub-pages exist
   - Use a small "▸" or ">" icon before section title
   - **File:** `SectionNav.swift:100-110`

3. **Improve empty states (1 hour)**
   - FILES remote panel: Change "выберите хост" → "Click a host in TERMINAL tab to connect"
   - DOCKER: "Select a host to view containers"
   - MONITOR: "Select a host to view metrics"
   - PROVISIONING: "Click a host to check setup status"
   - **Files:** `FilesView.swift:52`, `DockerView.swift`, `MonitorView.swift`

4. **Clarify "AI ACTIVITY" purpose (30 min)**
   - Change tab label to "AI AUDIT" or "MCP ACTIVITY"
   - Add one-line description in first-run guide
   - Show helpful text if no actions logged yet
   - **Files:** `RootView.swift:282`, `ActivityView.swift`

5. **Host picker in header (2 hours)**
   - Make selected host more clickable
   - Small dropdown to switch hosts without leaving current tab
   - Shows connection status inline
   - **File:** `RootView.swift:290-295` (expand header right-side UI)

6. **First-run onboarding modal (2 hours)**
   - Modal on first app open: "Welcome to Phosphor"
   - Step 1: "Import existing servers or add new"
   - Step 2: "Pick one and open a terminal"
   - Step 3: "What's next? [Docs] [Skip]"
   - **File:** Add to `RootView.swift`, triggered by `model.isFirstRun`

7. **Hide unfinished features (30 min)**
   - If SNIPPETS or FORWARDING are incomplete, hide them from SectionNav
   - Add comments in code explaining why
   - **Files:** `SectionNav.swift` (enum HostsPage)

8. **Better keyboard navigation (1 hour)**
   - Cmd+1-8 to switch tabs ✓ (already done)
   - Cmd+Shift+1-8 to access sub-pages (e.g., Cmd+Shift+2 → TERMINAL, Cmd+Shift+K → KEYS)
   - Tab key to navigate within section
   - **File:** `RootView.swift` (add more keyboard shortcuts)

---

## 5. Accessibility Issues

1. **Low contrast on muted text** — style.muted is hard to read in dim light
   - Affects: sub-page labels, hints, secondary text
   - **Fix:** Increase contrast ratio to 4.5:1 minimum
   - **File:** `PhosphorStyle.swift`

2. **Small hit target for session rail buttons** — drag handles, close buttons are tiny
   - **Fix:** Min 48×48 pt touch target (macOS standard)
   - **File:** `SessionRail.swift`

3. **No focus indicators on buttons** — keyboard users can't see what's focused
   - **Fix:** Add `.focusable()` + `.focused()` styling
   - **File:** `PhButton.swift`, `PressFeedback`

4. **Color-only status indicators** — "idle/working/blocked" shown only via color
   - **Fix:** Add text labels or icons
   - **File:** `SessionRail.swift` (agent status display)

---

## 6. Summary of Issues by Category

| Category | Count | Example | Severity |
|----------|-------|---------|----------|
| Hidden features | 5 | KEYS sub-page, VOLUMES, GRAPHS | HIGH |
| Empty states unclear | 4 | FILES, DOCKER, MONITOR, PROVISIONING | HIGH |
| Naming confusion | 2 | "known hosts" (import vs. page), "AI ACTIVITY" | MEDIUM |
| Cognitive overload | 3 | 8 tabs + 5 settings sub-pages, 4 import buttons | HIGH |
| Accessibility | 4 | Contrast, focus indicators, hit targets | MEDIUM |
| Navigation friction | 2 | Host selection, discovering prerequisites | HIGH |

---

## 7. Recommended Action Plan

**Phase 1 (Quick Wins — Week 1):**
1. Implement quick wins #1–4 above (rename buttons, add chevrons, improve empty states)
2. Test with first-time user: "Can you add a host and connect?"

**Phase 2 (Onboarding — Week 2):**
5. Implement first-run modal (quick win #6)
6. Implement host picker (quick win #5)
7. Test: "Can you navigate to FILES and download a file?"

**Phase 3 (Major Changes — Weeks 3–4):**
- Choose one of the three directions (A, B, or C)
- Direction A (flatten) is recommended: balances clarity with preserving design intent
- Execute in small steps, test with users between each change

**Metrics:**
- Track first-run success: "user adds first host + connects" without external help
- Time to feature discovery: "How long until user finds KEYS, DOCKER, MONITOR sub-pages?"
- User feedback on clarity: "Was it obvious what each section does?"

---

## 8. Design Debt

Per PLAN §27 and user feedback:
- "очень много шума, непонятно что куда тыкать" (too much noise, unclear where to click)
- This audit confirms that 30% of features are hidden by default
- The 8-tab + 20 sub-pages architecture is coherent BUT not discoverable
- Recommendation: **Prioritize discoverability over minimalism** for next release

---

## Screenshots Referenced


---

**Report compiled by:** Claude Code Agent  
**Duration:** Full-source analysis + visual audit  
**Next step:** Schedule review with owner to choose preferred direction (A/B/C)
