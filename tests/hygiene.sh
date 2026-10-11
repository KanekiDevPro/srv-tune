#!/usr/bin/env bash
# Hygiene gate (mirrors CI): fails on CRLF bytes and missing exec bits.
# Executable allowlist: directly-executed scripts. Sourced libs stay 644.
# shellcheck shell=bash
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# 1. No CR bytes in tracked text files.
while IFS= read -r f; do
  case "$f" in
  *.gif | *.png) continue ;;
  esac
  if grep -q $'\r' "$f" 2>/dev/null; then
    printf 'CRLF-FAIL: %s\n' "$f"
    fail=1
  fi
done < <(git ls-files)

# 2. Exec bit present on every directly-executed script.
while IFS= read -r f; do
  mode="$(git ls-files -s "$f" | awk '{print $1}')"
  if [[ "$mode" != "100755" ]]; then
    printf 'EXEC-FAIL: %s has mode %s\n' "$f" "$mode"
    fail=1
  fi
done < <(git ls-files | grep -E '^(optimizer\.sh|scanner/scan\.sh|tests/.*\.sh|tests/vm/.*\.sh)$')

if [[ "$fail" == "0" ]]; then
  printf 'hygiene: clean\n'
fi
exit "$fail"
