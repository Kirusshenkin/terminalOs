# Security policy

Phosphor holds SSH credentials, opens shells on your machines and starts AI
agents in terminal panes, so security reports are welcome and taken seriously.

## Reporting a vulnerability

Report privately through GitHub:
**[Security → Report a vulnerability](https://github.com/Kirusshenkin/terminalOs/security/advisories/new)**.
Do not open a public issue, pull request or discussion for a vulnerability.

Useful in a report: what an attacker controls, what they gain, and the shortest
path from one to the other. A proof of concept helps; it is not required.

## What happens next

- Acknowledgement within 7 days.
- An assessment — accepted, needs more information, or out of scope with the
  reason — within 14 days.
- A fix for a confirmed issue ships in a release as soon as it is ready; the
  advisory is published with the release, crediting you unless you ask not to.

This is a project maintained by one person, so the dates are honest upper
bounds rather than a service level.

## Safe harbor

Research done in good faith under this policy is welcome: we will not pursue
or support legal action against it. Test against your own machines and
accounts only, do not access or keep other people's data, and give us a
reasonable time to fix the issue before disclosing it.

## Scope

In scope:

- anything that leaks a secret (password, passphrase, private key, TOTP, the
  profile key) into logs, crash reports, the MCP audit log, error messages,
  the clipboard or disk;
- anything that lets untrusted server output — escape sequences, file names,
  container logs — execute, exfiltrate or misrepresent;
- weaknesses in host key verification, the encrypted profile, Keychain usage,
  sync between machines, or the update check and its signature;
- the MCP bridge: getting past the per-host access mode, the confirmation
  prompt or the command deny-list, or reaching the bridge socket from another
  user or process;
- AI agents started from the pane picker: an install or launch line that runs
  something other than what is shown, or an agent reaching beyond what it was
  started with.

Out of scope: bugs in the AI agents themselves (Claude Code, Codex, Gemini,
Cursor, opencode) — report those to their vendors; attacks that need an
already compromised Mac user account; denial of service by a server you
connected to on purpose; social engineering.

The full threat model — terminal escape sequences, the Terrapin mitigation,
MCP prompt injection — is in `docs/PLAN.md` §15.3 and §16.

## Supported versions

Only the latest release gets security fixes. The app checks for updates on its
own; install the update to get the fix.
