# Security policy

Phosphor holds SSH credentials and opens shells on your machines, so security
reports are welcome and taken seriously.

## Reporting a vulnerability

Please report privately through GitHub:
**Security → Advisories → Report a vulnerability** on this repository.
Do not open a public issue for a vulnerability.

Useful in a report: what an attacker controls, what they gain, and the shortest
path from one to the other. A proof of concept helps; it is not required.

## Scope

In scope: anything that leaks a secret (password, passphrase, private key,
TOTP) into logs, crash reports, the MCP audit log, error messages or disk;
anything that lets untrusted server output execute, exfiltrate or misrepresent;
weaknesses in host key verification, the encrypted profile, the Keychain
usage, or the MCP access policy.

The full threat model — including terminal escape sequence handling, the
Terrapin mitigation and MCP prompt injection — is in `docs/PLAN.md` §15.

## Supported versions

The project is pre-release. Until the first tagged release, only `main` is
supported.
