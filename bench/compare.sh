#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Compare two bench.json captures. Formats: markdown (default), json, html.
# Usage: bench/compare.sh BEFORE AFTER [--format md|json|html]
# shellcheck shell=bash
set -euo pipefail

BEFORE="${1:-}"
AFTER="${2:-}"
FORMAT="md"
for a in "$@"; do
  case "$a" in
  --format=*) FORMAT="${a#*=}" ;;
  esac
done
if [[ -z "$BEFORE" || -z "$AFTER" ]]; then
  printf 'usage: compare.sh BEFORE.json AFTER.json [--format md|json|html]\n' >&2
  exit 2
fi

jget() {
  grep -o "\"$2\":[^,}]*" "$1" 2>/dev/null | head -n 1 | cut -d: -f2- | tr -d ' "' || true
}

METRICS="latency_ms dns_ms mirror_s iperf_mbps sysbench_eps fio_iops"

row_md() {
  local m="$1" b="$2" a="$3" d
  if [[ "$b" == "null" || -z "$b" || "$a" == "null" || -z "$a" ]]; then
    printf '| %s | %s | %s | n/a |\n' "$m" "$b" "$a"
    return 0
  fi
  d="$(awk -v b="$b" -v a="$a" 'BEGIN{printf "%.1f", (a-b)/b*100}')"
  printf '| %s | %s | %s | %s%% |\n' "$m" "$b" "$a" "$d"
}

case "$FORMAT" in
md | markdown)
  printf '# temper benchmark comparison\n\n'
  printf '| metric | before | after | change |\n|---|---|---|---|\n'
  for m in $METRICS; do
    # shellcheck disable=SC2086
    row_md "$m" "$(jget "$BEFORE" $m)" "$(jget "$AFTER" $m)"
  done
  ;;
json)
  printf '{\n"before": '
  cat "$BEFORE"
  printf ',\n"after": '
  cat "$AFTER"
  printf '\n}\n'
  ;;
html)
  printf '<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="utf-8"><title>temper benchmark</title>\n'
  printf '<style>table{border-collapse:collapse}td,th{border:1px solid #999;padding:4px 8px}</style>\n'
  printf '</head>\n<body>\n<h1>temper benchmark comparison</h1>\n<table>\n<tr><th>metric</th><th>before</th><th>after</th><th>change</th></tr>\n'
  for m in $METRICS; do
    # shellcheck disable=SC2086
    r="$(row_md "$m" "$(jget "$BEFORE" $m)" "$(jget "$AFTER" $m)" | sed -e 's/^| //' -e 's/ |$//' -e 's/ | /<\/td><td>/g')"
    printf '<tr><td>%s</td></tr>\n' "$r"
  done
  printf '</table>\n</body>\n</html>\n'
  ;;
*)
  printf 'error: unknown format %s (md|json|html)\n' "$FORMAT" >&2
  exit 2
  ;;
esac
