#!/usr/bin/env bash
# Portable detection helpers shared by scanner and modules.
# Avoids GNU-only flags (uutils/coreutils compatible).
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_DETECT_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_DETECT_SOURCED=1

detect_virt() {
  if [[ -f /.dockerenv ]]; then
    printf 'docker\n'; return 0
  fi
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt 2>/dev/null || printf 'bare\n'
    return 0
  fi
  if grep -qi 'openvz' /proc/self/status 2>/dev/null; then
    printf 'openvz\n'; return 0
  fi
  printf 'unknown\n'
}

detect_cpu_cores() {
  if command -v nproc >/dev/null 2>&1; then
    nproc 2>/dev/null || printf '1\n'
  elif [[ -f /proc/cpuinfo ]]; then
    grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1\n'
  else
    printf '1\n'
  fi
}

detect_aesni() {
  grep -qi ' aes ' /proc/cpuinfo 2>/dev/null && printf 'yes\n' || printf 'no\n'
}

detect_mem_kb() {
  awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || printf '0\n'
}

detect_disk_type() {
  # Best-effort: NVMe > SSD > HDD > unknown. Rotational flag, portable.
  local rot=""
  for f in /sys/block/*/queue/rotational; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *nvme*|*vd*) printf 'NVMe\n'; return 0 ;;
    esac
    rot="$(cat "$f" 2>/dev/null || printf '')"
    if [[ "$rot" == "0" ]]; then
      printf 'SSD\n'; return 0
    fi
  done
  if ls /dev/nvme* >/dev/null 2>&1; then
    printf 'NVMe\n'; return 0
  fi
  if [[ -n "$rot" ]]; then
    printf 'HDD\n'; return 0
  fi
  printf 'unknown\n'
}
