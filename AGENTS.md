# Working in this repository

Phosphor is a macOS terminal with an SSH core, a Docker panel, server metrics
and an MCP server. Swift 6.3, macOS 26+, SwiftUI + AppKit, no Xcode project —
one SPM package.

## Commands

```sh
swift build
swift test            # 157 tests, all must stay green
./scripts/check.sh    # format + lint + build + test — run before every commit
```

`swift format` and `swiftlint` are configured in `.swift-format` and
`.swiftlint.yml`. Do not add formatting passes of your own.

## Where things are

```
Sources/PhosphorCore   shared primitives, no I/O
Sources/VaultKit       encrypted profile, atomic writes
Sources/HostsKit       hosts, groups, tags, ssh_config import
Sources/SSHKit         transport, proxies, jump hosts
Sources/TerminalCore   the emulator view (the only package allowed AppKit)
Sources/DockerKit      containers over SSH
Sources/MetricsKit     /proc parsing, ring buffers
Sources/KeysKit        authorized_keys, fingerprints
Sources/ProvisionKit   server setup recipes
Sources/MCPBridge      tool catalogue, access policy, audit log, socket
Sources/phosphor-mcp   the stdio shim that MCP clients launch
Sources/PhosphorUI     views and view models
docs/PLAN.md           the architecture plan (Russian) — read before big changes
docs/MCP.md            the MCP server, in English
```

## Rules that are not negotiable

Read [`CLAUDE.md`](CLAUDE.md) — it is the full version. The short list:

- **Plan first.** Requirements land in `docs/PLAN.md` before the code that
  implements them.
- **Code, names, comments and commit messages in English.** User-visible strings
  in both English and Russian, never hardcoded in one language.
- **Swift 6 strict concurrency** in every target. Network, parsing and disk work
  in actors; only view models on the main actor.
- **No swallowed errors.** No `try?` without a comment saying what is lost and
  why. Every user-facing error says what happened *and* what to do.
- **No secrets in logs, errors, crash reports or the MCP audit.** No `print`,
  ever — `Logger` with a category.
- **Bounded buffers, no allocation in the draw path**, polling pauses when the
  window is not visible, animations touch only `transform` and `opacity`.
- **No new dependency** for something a hundred lines of our own code can do.
- **No abstraction before the second implementation** and nothing built "for
  later".

Tests are required for pure functions where a silent mistake is expensive:
parsers, fingerprints, delta maths, profile encryption and migrations. The UI is
not covered by tests, and tests never touch the network.
