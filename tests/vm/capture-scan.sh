#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Capture scanner output next to manual commands, as root and non-root.
# Usage: tests/vm/capture-scan.sh <outdir>
# shellcheck shell=bash
set -euo pipefail

OUT="${1:-artifacts}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT"

run_scan() {
  local tag="$1"
  export SRV_TUNE_JSON_OUT="$OUT/scan-$tag.json"
  bash "$ROOT/scanner/scan.sh" >"$OUT/human-$tag.txt" 2>"$OUT/scan-$tag.err" || printf 'scan exit: %s\n' "$?" >"$OUT/scan-$tag.exit"
  unset SRV_TUNE_JSON_OUT
}

{
  printf '=== whoami ===\n'
  whoami
  id -u
  printf '=== lscpu / cpuinfo ===\n'
  (lscpu 2>/dev/null || head -n 20 /proc/cpuinfo) || echo CMD-MISSING
  printf '=== free ===\n'
  (free -m 2>/dev/null || grep -E 'MemTotal|SwapTotal' /proc/meminfo) || echo CMD-MISSING
  printf '=== lsblk ===\n'
  lsblk 2>/dev/null || echo CMD-MISSING
  printf '=== os-release ===\n'
  cat /etc/os-release 2>/dev/null || echo CMD-MISSING
  printf '=== kernel/init/virt ===\n'
  uname -r
  (systemd-detect-virt 2>/dev/null || echo no-systemd-detect-virt)
  printf '=== net ===\n'
  (ip route show default 2>/dev/null || echo no-ip-route)
  (cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo no-cc)
  printf '=== dns ===\n'
  (resolvectl status 2>/dev/null || cat /etc/resolv.conf 2>/dev/null) || echo CMD-MISSING
  printf '=== apt sources ===\n'
  (
    ls /etc/apt/sources.list.d/ 2>/dev/null
    cat /etc/apt/sources.list 2>/dev/null
  ) || echo CMD-MISSING
  printf '=== sshd -T (first 10) ===\n'
  (sshd -T 2>/dev/null | head -n 10 || echo no-sshd-T)
  printf '=== listening ports ===\n'
  (ss -tlnp 2>/dev/null || echo no-ss)
} >"$OUT/manual-root.txt" 2>&1 || true

run_scan root

# Non-root run (read-only scan must work without root).
if id nobody >/dev/null 2>&1; then
  chmod a+rX "$ROOT" "$ROOT/scanner" 2>/dev/null || true
  su nobody -s /bin/bash -c "SRV_TUNE_TEST=1 bash $ROOT/scanner/scan.sh" >"$OUT/human-nobody.txt" 2>"$OUT/scan-nobody.err" || true
  su nobody -s /bin/bash -c "id -u; cat /etc/os-release | head -3" >"$OUT/manual-nobody.txt" 2>&1 || true
else
  printf 'no-nobody-user\n' >"$OUT/human-nobody.txt"
fi

printf 'captured in %s\n' "$OUT"
ls -la "$OUT"
