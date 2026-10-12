#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Assert scan quality on real Linux: fields the scanner must not report as
# unknown when the image guarantees the source exists.
# Usage: tests/vm/assert-scan.sh <outdir>
# shellcheck shell=bash
set -euo pipefail

OUT="${1:-artifacts}"
JSON="$OUT/scan-root.json"
fail=0

need() {
  # need <file> <substr> <label>
  if ! grep -q "$2" "$1" 2>/dev/null; then
    printf 'ASSERT-FAIL: %s not found in %s\n' "$3" "$1"
    fail=1
  fi
}

[[ -f "$JSON" ]] || {
  printf 'ASSERT-FAIL: missing %s\n' "$JSON"
  exit 1
}

# Valid JSON object (jq if present, else python3, else brace check).
if command -v jq >/dev/null 2>&1; then
  jq empty "$JSON" || fail=1
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON" || fail=1
else
  grep -q '^{.*}$' "$JSON" || fail=1
fi

val() {
  grep -o "\"$1\":\"[^\"]*\"" "$JSON" | head -n 1 | cut -d'"' -f4
}

[[ "$(val OS_ID)" != "unknown" ]] || {
  printf 'ASSERT-FAIL: OS_ID unknown\n'
  fail=1
}
[[ "$(val OS_VERSION)" != "unknown" ]] || {
  printf 'ASSERT-FAIL: OS_VERSION unknown\n'
  fail=1
}
[[ "$(val DNS)" != "unknown" ]] || {
  printf 'ASSERT-FAIL: DNS unknown\n'
  fail=1
}
[[ "$(val MIRROR)" != "unknown" ]] || {
  printf 'ASSERT-FAIL: MIRROR unknown\n'
  fail=1
}
[[ "$(val PROFILE)" != "" ]] || {
  printf 'ASSERT-FAIL: PROFILE empty\n'
  fail=1
}

score="$(val SCORE)"
case "$score" in
'' | *[!0-9]*)
  printf 'ASSERT-FAIL: SCORE not numeric: %s\n' "$score"
  fail=1
  ;;
*) [[ "$score" -ge 0 && "$score" -le 100 ]] || {
  printf 'ASSERT-FAIL: SCORE out of range: %s\n' "$score"
  fail=1
} ;;
esac

# CPU_CORES must equal nproc where nproc exists.
if command -v nproc >/dev/null 2>&1; then
  [[ "$(val CPU_CORES)" == "$(nproc)" ]] || {
    printf 'ASSERT-FAIL: CPU_CORES %s != nproc %s\n' "$(val CPU_CORES)" "$(nproc)"
    fail=1
  }
fi

# RAM_KB must be > 0 on real Linux.
[[ "$(val RAM_KB)" != "0" && "$(val RAM_KB)" != "" ]] || {
  printf 'ASSERT-FAIL: RAM_KB is %s\n' "$(val RAM_KB)"
  fail=1
}

need "$OUT/human-root.txt" "Recommended profile" "human report profile line"
need "$OUT/human-nobody.txt" "Recommended profile" "non-root human report"

if [[ "$fail" == "0" ]]; then
  printf 'assert-scan: all checks passed\n'
fi
exit "$fail"
