<div align="center">

# Phosphor

**A macOS terminal that also runs your servers.**

Shell, Docker, metrics, keys and files — over one SSH connection per host.
Unlocked with your fingerprint. Green on black, because that is how it should look.

*SSH client · Docker manager · server monitor · SFTP · `authorized_keys` editor ·
MCP server for Claude Code and Claude Desktop · macOS 26 · Swift 6 · MIT*

</div>

![Terminal](docs/images/01-terminal.png)

---

## The problem

You keep four windows open to do one job. A terminal for the shell. A second
terminal for `docker logs -f`. A third for `htop`. A browser tab for whatever
dashboard someone installed on the box. Each of them logs in separately, each
one asks for the key passphrase again, and none of them knows what the others
are looking at.

Phosphor opens **one SSH connection per host** and multiplexes everything
through it — the interactive shell, container logs, `docker` commands, `/proc`
snapshots, SFTP transfers, port forwards. One login. One tunnel through your
proxy. One place where the state lives.

And because that state is already in the app, it also exposes an **MCP server**:
Claude Code and Claude Desktop can use your servers through your connections,
your keys and your access policy — with every call written to an audit log.

---

## What it does

### Docker, without leaving the terminal

![Docker](docs/images/02-docker.png)

The container list is a sidebar, not a separate app. Inspect, stats, mounts,
environment and live logs with `--tail` and a filter, streamed over the SSH
connection you already have. Environment values whose name looks like a secret
(`PASS`, `KEY`, `TOKEN`, `SECRET`) are masked in the UI and never copied into
the audit log.

No Docker Engine API to expose, no socket to tunnel: it shells out to `docker`
with JSON output, which works on every box where Docker already runs.

### Metrics that cost one channel

![Metrics](docs/images/03-metrics.png)

Per-core load, memory with the cache broken out, disks, network, and per
container CPU and memory — from `/proc` snapshots taken over a single
long-lived channel. No agent to install on the server, no swarm of exec
channels. Polling stops when the window is hidden, and every buffer has a
ceiling.

### Hosts, groups and tags

![Hosts](docs/images/04-hosts.png)

One group per host, as many tags as you like. The group carries the settings —
how to reach it, which key, which theme, what MCP is allowed to do — and tags
are just for finding things. Import `~/.ssh/config` and keep going.

### Unlock with a fingerprint

![Touch ID](docs/images/05-touch-id.png)

Phosphor has no account and no password of its own. There is a profile on this
Mac, and your fingerprint opens it. Passwords, passphrases and TOTP seeds live
in the Keychain behind biometrics; keys can live in the Secure Enclave, where
they cannot be copied off the machine at all. Risky actions ask again.

### A new server, set up by a recipe

![Provisioning](docs/images/06-provisioning.png)

Connect to a fresh box and Phosphor probes it: what is installed, what is
listening, whether anyone has been here before. If it is empty, it offers a
recipe — packages and unattended upgrades, Docker with log size caps, nginx,
certbot, a firewall that only opens 22/80/443, and finally disabling password
login. Every step is idempotent, every step shows the exact commands, and the
lockout guard means password login is closed only after a second key-based
connection has proved it works.

### Keys you can actually see

![Keys](docs/images/09-keys.png)

`authorized_keys` as a table instead of a text file: fingerprints computed
locally, weak RSA flagged, options shown, disabled entries kept as comments.
The key you are currently connected with cannot be removed without an explicit
confirmation, writes are atomic, and a backup stays on the server.

### Files on both sides

![SFTP](docs/images/08-sftp.png)

Two panes, drag between them or in from Finder. Same SSH connection, same
proxy. A dropped transfer resumes where it stopped.

### Make it yours

![Theme](docs/images/07-theme.png)

Themes are plain JSON in `themes/` — keep them in git, trade them with people,
import `.itermcolors`, alacritty and base16. Palette, font, ligatures, line
height, background image, scanlines, glow, vignette, window opacity. Bind a
theme to a group so production is unmistakably red.

And there is a cat in the corner. Or a sugar glider. It sleeps while the app is
locked, it never covers your output, and one switch turns it off forever.

---

## Give an agent your servers without giving it your keys

Phosphor is also a **Model Context Protocol server**. Register one command and
Claude Code, Claude Desktop, Cursor or any other MCP client can list your hosts,
read metrics, inspect containers, follow logs and — when you allow it — run
commands, restart containers and manage `authorized_keys`.

The difference from handing a model a shell: **the app holds the connection, the
agent holds nothing.**

| | Shell tool with raw `ssh` | Credentials in an MCP config | Phosphor |
|---|---|---|---|
| Where the key lives | on disk, agent-readable | on disk, agent-readable | Keychain / Secure Enclave, behind Touch ID |
| What is reachable | everything | everything | only hosts you enabled, in the mode you set |
| `rm -rf /` | runs | runs | refused by a deny-list that overrides every mode |
| Human in the loop | none | none | per-write confirmation, grants expire in 15 min |
| Trail afterwards | shell history, maybe | none | an audit log with no writing tool |
| Secrets in output | whatever is on screen | whatever is on screen | masked before the model sees them |
| Runaway loop | unbounded | unbounded | rate-limited writes |

```sh
claude mcp add phosphor /Applications/Phosphor.app/Contents/MacOS/phosphor-mcp
```

In the MCP registry it is `io.github.Kirusshenkin/phosphor`; every release also
ships a `.mcpb` bundle with a published SHA-256 for clients that install that
way.

Nine tools, six of them read-only. Every host starts `disabled` — nothing is
reachable until you choose `read-only`, `confirm` or `full` for it, and
production servers are meant to stay `read-only`. A compromised server can put
anything it likes into a log line the model reads; it still cannot grant itself
a mode, get past the deny-list, or erase the record of trying.

**Full details: [`docs/MCP.md`](docs/MCP.md)** — tool catalogue, policy, audit,
and the exact error the agent gets when the app is closed, locked or refusing.

## Principles

**No integrations.** The only network traffic the app makes is SSH to your own
servers and the update feed. No telemetry, no accounts, no third-party
services, nothing phoning home.

**Secrets stay secret.** Never in a log line, a crash report, an MCP audit
entry or an error message. Terminal scrollback is not written to disk by
default.

**Errors tell you what to do.** "Could not connect" is a bug. "The proxy at
127.0.0.1:10808 is not answering — is V2Box running?" is an error message. The
app distinguishes a dead proxy from an unreachable server from a refused
credential, because otherwise diagnosis is guesswork.

**It stays fast because it is open all day.** Bytes from the network are
batched into ~16 ms windows before they reach the emulator, the draw path
allocates nothing, every buffer is bounded, polling stops when the window is
not visible, and animations only ever touch `transform` and `opacity`.

**Strict Swift 6 concurrency**, in every target, with no escape hatches.
Network, parsing and disk work live in actors; only view models are on the main
actor.

**Two languages.** English and Russian, both through a String Catalog. Not one
hardcoded interface string — a linter checks.

---

## Status

Builds, runs, **150 tests green**. Ten screens: lock, hosts, terminal, files,
Docker, monitor, keys, provisioning, AI activity. Interface in Russian and
English.

What works against a real server: SSH over one multiplexed connection per host,
container listing with actions and streaming logs, `/proc` metrics, reading and
editing `authorized_keys`, provisioning recipes, both file panes, and an
interactive shell that rides the same socket.

MCP works end to end: an `phosphor-mcp` shim ships inside the bundle, speaks
JSON-RPC over stdio and proxies to a local socket the app owns. Every host
starts disabled, writes need a decision from a person, a deny-list overrides
every mode, and the audit log has no writing tool — the model can act but
cannot erase its trail.

What is not built yet: the native Citadel transport (the process-based one is
tested and works) and importing hosts from Termius.

Idle CPU is zero — no timers, polling pauses when the window is in the
background.

## Install

```sh
curl -fsSL https://github.com/Kirusshenkin/terminalOs/releases/latest/download/Phosphor.zip -o Phosphor.zip
unzip -q Phosphor.zip -d /Applications
xattr -dr com.apple.quarantine /Applications/Phosphor.app
```

Or download `Phosphor.zip` from the release page and drag the app into
Applications.

**macOS will warn you the first time.** The app is ad-hoc signed — there is no
Apple Developer certificate behind it — so everything downloaded from the
internet lands in quarantine. This is not damage:

1. Double-click the app, dismiss the warning.
2. System Settings → Privacy & Security → scroll down → **Open Anyway**.
3. Confirm. It never asks again.

The `xattr` command above does the same thing in one step.

Every release ships `SHA256SUMS.txt`; verify with
`shasum -a 256 -c SHA256SUMS.txt`.

There is no in-app updater yet — check the releases page. The version you are
running is in the About panel.

### For AI agents

Each release carries `latest.json`, so nothing has to be scraped:

```sh
curl -fsSL https://github.com/Kirusshenkin/terminalOs/releases/latest/download/latest.json
```

```json
{
  "version": "0.1.0",
  "url": "https://github.com/.../Phosphor-0.1.0.zip",
  "sha256": "…",
  "mcp": { "command": "/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp",
           "transport": "stdio" }
}
```

The bundle contains an MCP stdio shim. Register it and Phosphor exposes its
tools:

```json
{
  "mcpServers": {
    "phosphor": {
      "command": "/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp"
    }
  }
}
```

The shim talks to the running app over a Unix socket in the user's home
directory; it carries no credentials of its own. If the app is closed or locked
it says so and every tool call fails closed — MCP access is off by default and
has to be granted in the app, per session, with a fingerprint.

## Releasing

Tag and push:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/release.yml` runs the tests, then `.github/scripts/package.sh` —
which is the same script used locally, so a release can always be reproduced on
your own machine:

```sh
MARKETING_VERSION=0.1.0 BUILD_NUMBER=1 ./.github/scripts/package.sh
```

It produces `dist/Phosphor-<version>.zip`, a copy named `Phosphor.zip` (only an
exact filename works behind `/releases/latest/download/`), `SHA256SUMS.txt` and
`latest.json`. The workflow unzips the archive again and runs
`codesign --verify` on it before publishing: a bundle whose signature does not
survive the round trip will not open on anyone's machine.

## Build

Requires macOS 26+ and a Swift 6.3 toolchain.

```sh
git clone https://github.com/Kirusshenkin/terminalOs.git
cd terminalOs
swift build
swift test
./.github/scripts/check.sh     # format, lint, build, tests — before every commit
```

## Layout

```
Sources/          PhosphorCore, VaultKit, HostsKit, SSHKit, DockerKit,
                  MetricsKit, KeysKit, ThemeKit, ProvisionKit, PhosphorUI
design/           UI artboards (.dc.html), one per screen
docs/PLAN.md      The full architecture plan, in Russian
docs/images/      Screenshots rendered from the artboards
```

## Contributing

The plan comes first — requirements land in [`docs/PLAN.md`](docs/PLAN.md)
before any code. Conventions worth knowing before a pull request: code, names
and commit messages in English; user-visible strings in both English and Russian
through `Strings`, never hardcoded; strict Swift 6 concurrency in every target;
no swallowed errors, and every message says what happened *and* what to do; no
secrets in logs, errors or the audit; bounded buffers and nothing allocated in
the draw path.

## Security

Please report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md).
The threat model is `docs/PLAN.md` §15.

## License

[MIT](LICENSE)
