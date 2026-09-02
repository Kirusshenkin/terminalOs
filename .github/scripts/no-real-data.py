#!/usr/bin/env python3
"""Keeps real infrastructure out of the repository.

It has already happened once: real addresses and host names reached public
history through test fixtures and design mockups, and cleaning them meant
rewriting every commit. A check before the commit is cheaper than a rewrite
after the push.

Addresses in examples, fixtures and screenshots belong to the ranges reserved
for documentation (RFC 5737) or to private ranges. Anything else is a real
machine somewhere — ours or a stranger's — and neither belongs here.
"""

import ipaddress
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SELF = ".github/scripts/no-real-data.py"

# Имена, которые утекли однажды. Список дополняется, а не сокращается.
BANNED_NAMES = re.compile(r"\b(valor|lafa|slotgo)\b", re.IGNORECASE)
PRIVATE_KEY = re.compile(r"BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY")
# Четыре октета, не окружённые цифрами: версия 1.20.0 сюда не попадает.
ADDRESS = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])")
DOCUMENTATION = ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")
PLACEHOLDERS = {"1.2.3.4", "5.6.7.8", "8.8.8.8"}


def allowed(address: str) -> bool:
    try:
        value = ipaddress.IPv4Address(address)
    except ValueError:
        return True  # 256.1.1.1 и прочее — не адрес, а строка в тесте
    if value.is_private or value.is_loopback or value.is_unspecified:
        return True
    if value.is_reserved or value.is_multicast or value.is_link_local:
        return True
    if any(value in ipaddress.IPv4Network(net) for net in DOCUMENTATION):
        return True
    return address in PLACEHOLDERS


def problems_in(name: str, text: str) -> list[str]:
    found: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        for address in ADDRESS.findall(line):
            if not allowed(address):
                found.append(f"{name}:{number}: адрес {address}")
        if PRIVATE_KEY.search(line):
            found.append(f"{name}:{number}: приватный ключ")
        banned = BANNED_NAMES.search(line)
        if banned:
            found.append(f"{name}:{number}: имя «{banned.group(0)}»")
    return found


def main() -> int:
    listing = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
    )

    problems: list[str] = []
    for name in listing.stdout.split():
        if name == SELF:
            continue
        try:
            text = (ROOT / name).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        problems.extend(problems_in(name, text))

    if problems:
        print("реальные данные в репозитории:")
        for problem in problems:
            print(f"  {problem}")
        print("\nЗамени на диапазоны RFC 5737 (192.0.2.x, 198.51.100.x,")
        print("203.0.113.x) и вымышленные имена.")
        return 1

    print("✓ ни реальных адресов, ни ключей")
    return 0


if __name__ == "__main__":
    sys.exit(main())
