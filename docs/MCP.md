# Phosphor as an MCP server

**Model Context Protocol server for SSH, Docker and Linux server metrics on
macOS.** Phosphor is a native macOS terminal that already holds authenticated
SSH connections to your servers; the MCP bridge lets Claude Code, Claude
Desktop, Cursor or any other MCP client use those connections — without ever
seeing a key, a password or a passphrase.

- **Transport:** stdio shim → Unix socket → the running app
- **Tools:** 9, closed catalogue (6 read, 3 write)
- **Auth:** the app is unlocked by Touch ID; the agent inherits a session, not a credential
- **Default:** every host is `disabled` until you say otherwise
- **Audit:** every call is recorded, and no tool can erase the record

---

## Why route an agent through a terminal app

An agent that manages servers usually gets there one of two ways: you paste
credentials into a config file, or you give it a shell tool and hope. Both hand
over a long-lived secret and leave no trace anyone can read afterwards.

Phosphor is a third way: **the app holds the connection, the agent holds
nothing.**

| | Raw `ssh` in a shell tool | Credentials in an MCP config | Phosphor bridge |
|---|---|---|---|
| Where the private key lives | on disk, readable by the agent | on disk, readable by the agent | Keychain / Secure Enclave, behind Touch ID |
| What the model can reach | everything, always | everything, always | only hosts you enabled, in the mode you set |
| Destructive commands | whatever the model types | whatever the model types | deny-list overrides every mode |
| Human in the loop | none | none | per-write confirmation, expiring grants |
| Record of what happened | shell history, maybe | none | audit log the model cannot write to |
| Secrets in tool output | whatever is on screen | whatever is on screen | masked before the model sees them |
| Cost of an unattended loop | unbounded | unbounded | rate-limited writes |

The agent gets more useful context than a shell would give it (structured
container state, parsed `/proc` metrics, fingerprinted keys) and less power than
a shell would give it. That trade is the whole point.

---

## Setup

Registry name: **`io.github.kirusshenkin/phosphor`** — every release publishes a
`server.json` and a `phosphor-mcp-<version>.mcpb` bundle with its SHA-256, so a
client that installs from the [MCP registry](https://registry.modelcontextprotocol.io)
gets the shim verified before it runs.

The bundle is the shim, not the app: **Phosphor.app has to be installed and
unlocked**, otherwise every call fails closed with a message saying which of the
two is missing.

Install Phosphor, unlock it once, then register the shim that ships inside the
bundle:

```json
{
  "mcpServers": {
    "phosphor": {
      "command": "/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp"
    }
  }
}
```

Claude Code, in one line:

```sh
claude mcp add phosphor /Applications/Phosphor.app/Contents/MacOS/phosphor-mcp
```

The shim is a few kilobytes of JSON-RPC proxy. It carries no credentials, opens
no network sockets, and talks only to a Unix socket owned by the running app. If
the app is closed or locked, every call fails closed with an error that says
which of the two it was.

Then, in the app: **Hosts → the host → MCP mode.** Nothing is reachable until
you pick a mode there.

---

## Tools

Nine tools, deliberately. Every one of them is a door into your infrastructure,
so "let's add one more" costs more than it looks.

| Tool | What it returns or does | Class |
|---|---|---|
| `list_hosts` | Configured servers, groups, tags, connection state | read |
| `host_metrics` | Per-core CPU, memory, disks, network, uptime, load | read |
| `list_containers` | Containers with state, health, CPU and memory | read |
| `container_logs` | Last N log lines, with a filter | read |
| `container_inspect` | Full `docker inspect` for one container | read |
| `list_authorized_keys` | Keys on the server, with SHA256 fingerprints | read |
| `run_command` | Run a command on a host | **write** |
| `container_action` | `start` / `stop` / `restart` / `rm` | **write** |
| `manage_authorized_key` | Add or remove a key | **write** |

Read tools never mutate anything and never return a secret. Write tools always
go through the policy below.

---

## Access policy

Four modes, set per host — not globally, and not per agent:

| Mode | Meaning |
|---|---|
| `disabled` | Nothing. **The default for every new host**, including ones you forgot about. |
| `read-only` | Read tools answer, write tools are refused with a reason. Recommended for production. |
| `confirm` | Write tools raise a dialog in the app showing the exact command and host. |
| `full` | Write tools run without asking — the deny-list still applies. |

On top of the modes:

- **Deny-list first.** Patterns like `rm -rf /`, `mkfs`, `dd of=/dev/`,
  `shutdown` and fork bombs are refused before the mode is even consulted.
  `full` does not open them.
- **Grants expire.** A confirmation is good for 15 minutes, not forever — a
  permanent "yes" turns confirmation into a formality.
- **Writes are rate-limited** (20 per minute by default), so a looping agent
  cannot turn a bad idea into a hundred bad ideas.
- **Confirmation dialogs time out into refusal**, not into approval.
- **Secrets are never returned.** Private keys and passwords are not exposed by
  any tool; `run_command` does not interpolate stored secrets into commands;
  container environment values named `PASS`, `KEY`, `TOKEN` or `SECRET` are
  masked before they reach the model.

## Audit

Every call — timestamp, host, tool, arguments, result — lands in the audit log,
visible in the app's **AI activity** tab. There is no tool for writing to,
editing or clearing that log: the model can act, but it cannot clean up after
itself.

This is also the practical answer to prompt injection. A compromised server can
put anything into a log line or a container name, and that text reaches the
model as tool output. It cannot grant itself a mode, it cannot bypass the
deny-list, and whatever it does try shows up in a log a person can read.

## Failure modes, and what the agent is told

Diagnosis should not require guessing, so the errors are specific:

- app not running → *"Phosphor is not running"* (the shim can offer to launch it)
- app locked → *"Phosphor is locked — unlock with Touch ID"*
- host disabled → *"MCP is disabled for this host"*
- read-only host, write tool → *"this host is read-only"*
- deny-listed command → the pattern that matched
- confirmation timed out → *"no answer from the person"*
- proxy down vs. server down vs. auth refused → three different messages, never one generic one

## See also

- [README](../README.md) — what Phosphor is
- [PLAN.md](PLAN.md) §15 — the MCP design in full (Russian)
- [PLAN.md](PLAN.md) §16 — the threat model, including MCP prompt injection
- [SECURITY.md](../SECURITY.md) — reporting a vulnerability
