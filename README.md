<div align="center">

# Phosphor

**A macOS terminal that also runs your servers.**

Shell, Docker, metrics, keys and files — over one SSH connection per host.
Unlocked with your fingerprint. Green on black, because that is how it should look.

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

Early. The architecture is settled and written down in detail; the code is at
the beginning. **There is nothing to install yet.** The screenshots above are
the design, rendered from the artboards in [`design/`](design) — the app is
being built to match them.

| | |
|---|---|
| Э0 | Project skeleton, packages, CI |
| Э1 | Terminal core, tabs and splits, themes |
| Э2 | SSH, hosts, encrypted profile, known_hosts |
| Э3 | Proxies, SOCKS5, jump hosts |
| Э4 | Touch ID, biometric lock, TOTP |
| Э5 | Docker panel |
| Э6 | Metrics and charts |
| Э7 | Keys, SFTP, port forwards, snippets |
| Э8 | Host probing and provisioning recipes |
| Э9 | MCP server, tool policy, audit |
| Э10 | Settings, signing, Sparkle updates, release pipeline |

Updates will ship through Sparkle with EdDSA-signed appcasts, so the Gatekeeper
warning is a first-install thing and never happens again.

---

## Build

Requires macOS 26+ and a Swift 6.3 toolchain.

```sh
git clone https://github.com/Kirusshenkin/terminalOs.git
cd terminalOs
swift build
swift test
./scripts/check.sh     # format, lint, build, tests — before every commit
```

## Layout

```
Sources/          PhosphorCore, VaultKit, HostsKit, SSHKit, DockerKit,
                  MetricsKit, KeysKit, ThemeKit, ProvisionKit, PhosphorUI
design/           UI artboards (.dc.html), one per screen
docs/PLAN.md      The full architecture plan, in Russian
docs/images/      Screenshots rendered from the artboards
CLAUDE.md         Conventions: language, concurrency, errors, secrets, perf
```

## Contributing

The plan comes first — requirements land in [`docs/PLAN.md`](docs/PLAN.md)
before any code. The conventions in [`CLAUDE.md`](CLAUDE.md) apply to everyone,
not just to the machines.

## Security

Please report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md).
The threat model is `docs/PLAN.md` §15.

## License

[MIT](LICENSE)
