#!/bin/bash
# Прогон перед коммитом: формат, линт, сборка, тесты.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0

echo "==> swift format"
swift format lint --recursive --parallel Sources 2>/dev/null || fail=1

echo "==> swiftlint"
swiftlint lint --quiet || fail=1

if [ -f Package.swift ]; then
  echo "==> build"
  swift build || fail=1
  echo "==> tests"
  swift test || fail=1
fi

[ $fail -eq 0 ] && echo "✓ чисто" || echo "✗ есть замечания"
exit $fail
