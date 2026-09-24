# Phosphor: first run

Instructions for those opening Phosphor for the first time. Ten minutes — and
you'll have a list of servers, a terminal with sessions that survive window
close, Docker and metrics in one place.

Phosphor is an app for macOS 26 and newer. There is no account, there is no
Phosphor server: everything is stored on your Mac in encrypted form.

## 1. Installation

```sh
curl -fsSL https://github.com/Kirusshenkin/terminalOs/releases/latest/download/Phosphor.zip -o Phosphor.zip
unzip -q Phosphor.zip -d /Applications
xattr -dr com.apple.quarantine /Applications/Phosphor.app
```

Or download `Phosphor.zip` from the release page and drag the app into
Applications.

**macOS will warn you the first time.** The app has no Apple Developer
certificate, so everything downloaded from the internet lands in quarantine.
This is not damage:

1. Double-click the app, dismiss the warning.
2. System Settings → Privacy & Security → scroll down → **Open Anyway**.
3. Confirm. It never asks again.

The `xattr` command above does the same thing in one step.

## 2. Unlock

The app opens with a lock screen. **Tap the circle** with the label "touch the
sensor" and confirm with:

- **Touch ID**, if your Mac or keyboard has a sensor;
- **Apple Watch**, if unlock with watch is enabled;
- **your macOS account password**, if you have neither.

Phosphor has no login or password of its own. Below the circle it says which
unlock methods are available on this machine.

When a profile already exists, confirmation is asked twice in a row: the first
opens the window, the second unlocks the key that encrypts the profile. This is
how it works for now (issue #5).

## 3. Add servers

The first screen says "The list is empty — not for long". Phosphor has already
looked at what is on this machine and offers to import:

| Line | Takes from |
|---|---|
| import ~/.ssh/config | `Host` blocks with `HostName`, `User`, `Port` |
| known hosts | servers you have already connected to via `ssh` |
| import from Termius | Termius connection history |

Tap **take** next to the line you want. After import, to the right of the
buttons you see how many were added and how many were not recognized.

Later, the same thing is on the hosts page: the **import…** button shows a list
of sources. Add a server by hand: **add host** or **⌘N**.

- **address** — IP or name, like `example.com`;
- **user** — default `root`;
- **port** — default `22`;
- **name** — optional, the address is used if missing;
- **tags** — comma-separated, they power search;
- **how to reach it** — "direct" or "proxy". For proxy, give the host and port
  of your SOCKS5, like `127.0.0.1` and `10808` for V2Box.

Need to log in once without saving the server? Type `user@host` or
`user@host:port` in the search field and tap **connect**. After login,
Phosphor will ask to remember it.

## 4. Before connecting to a new server

Phosphor connects through the system `ssh` and checks the server key strictly.
The app cannot ask you to trust a new server yet, so **connect to a server you
have never used before through the regular Terminal first**:

```sh
ssh user@host
```

Check the fingerprint against what your host provider shows, and answer `yes`.
After that, Phosphor connects on its own.

Login is **by key**. Phosphor uses the same keys that `ssh` does: from `~/.ssh`
and from `ssh-agent`. Password login is not yet supported.

## 5. Connect

Tap the server card. The **terminal** tab opens, above it — a status line:
"building the host profile…", then the server's OS and uptime.

Faster from the keyboard: **⇧⌘O**, start typing the name, address or tag, ↑↓
and Enter. A server not in the list — type `user@host` or `user@host:port`.
Switch to another server from the header: tap the host name on the right.

If connection fails, the status line tells you what happened:

| Message | What to do |
|---|---|
| proxy 127.0.0.1:10808 is not answering — is V2Box running? | Start the proxy or check the port in the server card |
| … refused access — is your key missing from authorized_keys? | Add your public key to the server or check the user |
| the host key of … changed — connection stopped | The server was reinstalled — or someone is intercepting. Find out before "forgetting" the key in known hosts |
| … is not answering | Server is off, the address is wrong or the port is blocked by firewall |

## 6. Terminal and sessions

To the left of the terminal — a column:

- **"this Mac"** — "local shell" and local tmux sessions. The **+** button
  appears if tmux is on the Mac (`brew install tmux`).
- **"sessions"** — tmux sessions on the server. **+**, name, Enter — new
  session. Close the window or the app — the session keeps running on the
  server, and when you log back in, everything is there. Needs tmux on the
  server (`apt install tmux`). Right-click → **kill session on server**
  finishes it and everything inside.
- **"spaces"** — servers open right now. Switch with one tap.

Above the terminal — **split** button — up to four panes, each with its own
session. The icon next to it changes the orientation. Splits work on server
sessions; "this Mac" is one stream.

If a program in some session is waiting for input (say, an AI agent is asking a
question), a yellow dot lights up next to "terminal" in the header — visible
from any tab. The column on the left names the agent (Claude Code, Codex,
Aider…) and shows whether it is working or waiting — in tmux sessions and in
the plain shell of this Mac alike.

## 7. The other tabs

Tabs in the header switch with the mouse or keyboard:

| Keys | Tab | What is there |
|---|---|---|
| ⌘1 | hosts | server list, keys, port forwarding, snippets, known hosts, log |
| ⌘2 | terminal | sessions and panes |
| ⌘3 | files | left is this Mac, right is the server. **←** download, **→** upload, files can be dragged from Finder |
| ⌘4 | docker | containers, their state and actions. **kill** and **remove** ask for confirmation |
| ⌘5 | monitor | cores, memory, disks, network, heavy processes, graphs |
| ⌘6 | provisioning | basic setup of a fresh Ubuntu server |
| ⌘7 | ai access | Claude and other AI clients' access to servers, log of their actions |
| ⌘8 | settings | theme, glass, language, behaviour, profile |

Other keys are in the menu bar, next to the action (**File**, **Terminal**,
**Host**). The most useful:

| Keys | What it does |
|---|---|
| ⌘T | new session where you are now (on the server or on this Mac) |
| ⌘D / ⇧⌘D | split side by side / split below |
| ⌥⌘→ / ⌥⌘← | cursor to the next pane |
| ⌘W | close pane (server session stays) |
| ⌘K | clear terminal |
| ⌘F, ⌘G, ⇧⌘G | find in output, next, previous |
| ⌘= / ⌘- / ⌘0 | bigger / smaller / actual size text |
| ⇧⌘R | reconnect to server and raise fallen panes |
| ⇧⌘O | quick connect |
| ⌘N, ⌘E, ⌘⌫ | new host, edit open, delete open (with confirmation) |
| ⌘, | settings |
| ⌃⌘L | lock |
| ⌃` | bring Phosphor forward from any app (turn on in settings → behaviour) |

Inside the window Phosphor does not use ⌃-combos, ⌥ or ⌘←/→ — they go to the terminal.
Drag the line between panes to resize them; double-click it to split in half again.

**Provisioning changes the server:** installs packages, Docker and nginx,
turns on firewall and closes password login. Run it only on a fresh server
where SSH listens on port 22, and tap **what goes to the server** first.

## 8. Back up your profile

The key that encrypts the profile lives only on this Mac. If it is gone — Touch ID
fingerprints changed, system reinstalled, new Mac — the profile cannot be opened
without a backup.

**⌘8 → profile → export profile…**. Think up a passphrase and save the file
somewhere safe. The passphrase cannot be recovered: forget it and the file is
useless.

To restore the profile or move it to another Mac: **import profile…**, pick the
file and type the passphrase. The current server list is replaced with what is
in the file.

## 9. Connect an AI client (optional)

Phosphor can let Claude Code, Claude Desktop and other MCP clients work with
your servers — without handing over your keys.

1. **Claude Code:** open **⌘7 → access**, block "register Claude Code", click
   "copy" and run the command in a regular terminal. It looks like this:

   ```sh
   claude mcp add --scope user phosphor -- /Applications/Phosphor.app/Contents/MacOS/phosphor-mcp
   ```

   `--scope user` matters: without it the bridge is only seen in the folder where
   you ran the command. The status line in the same block shows whether Claude
   Code sees the bridge everywhere, in one folder, or not at all.

   **Claude Desktop and other clients** — add to their settings:

   ```json
   {
     "mcpServers": {
       "phosphor": {
         "command": "/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp"
       }
     }
   }
   ```

2. Phosphor must be open and unlocked.
3. **⌘7 → access.** Every server is **off** by default. Turn on the mode you
   want for the ones you need: "read only", "with confirmation" or "full".
   Write actions in "with confirmation" mode show up as a dialog for you, and
   without "allow" nothing runs. When several arrive at once they queue up: the
   dialog shows the first, and **⌘7 → access** lists them all under "waiting for
   your answer", with "deny all" for when an agent heads the wrong way. A
   request nobody answers within a minute is denied.
4. Everything the AI did is logged at **⌘7 → journal**. The AI has no tool to
   erase this log.

## 10. If something goes wrong

- **Lock screen does not take Touch ID.** Tap the circle again and pick
  password unlock. After a few failed tries, macOS temporarily blocks
  biometrics — this is also lifted by password.
- **Yellow bar "profile not saved…" or "profile is not being saved…"** above
  the tabs. Changes will be gone when the window closes. Do a profile export
  (section 8) and report the issue, quoting the bar text.
- **Yellow bar "…changes are not being written so the profile is not overwritten
  with an empty one…".** The profile file exists but did not open: Touch ID
  fingerprints changed, the key is lost or the file is damaged. The window is
  empty and Phosphor is on purpose not writing to avoid wiping real servers.
  Restore the profile from an export (section 8).
- **A server from import does not connect,** but `ssh` works from the Terminal.
  Check the user and port in the card: import from known hosts and Termius
  history does not know the user and fills in the Mac user name.
- **Found a vulnerability** — do not open a public issue, see `SECURITY.md`.
