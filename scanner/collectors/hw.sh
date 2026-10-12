#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Hardware collector (read-only).
# shellcheck shell=bash

collect_hw() {
  local cores="1" aes="no" ram="0" swap="0" disk="unknown" free="0"
  if command -v nproc >/dev/null 2>&1; then
    cores="$(nproc 2>/dev/null || printf '1')"
  fi
  if grep -qi ' aes ' /proc/cpuinfo 2>/dev/null; then
    aes="yes"
  fi
  ram="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  swap="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  if [[ -z "$ram" ]]; then ram="0"; fi
  if [[ -z "$swap" ]]; then swap="0"; fi
  local f rot=""
  for f in /sys/block/*/queue/rotational; do
    [[ -f "$f" ]] || continue
    case "$f" in
    *nvme* | *vda*)
      disk="NVMe"
      break
      ;;
    esac
    rot="$(cat "$f" 2>/dev/null || printf '')"
    if [[ "$rot" == "0" ]]; then disk="SSD"; else disk="HDD"; fi
  done
  if [[ "$disk" == "unknown" ]] && ls /dev/nvme* >/dev/null 2>&1; then
    disk="NVMe"
  fi
  free="$(df -k / 2>/dev/null | awk 'NR==2{print $4}' || true)"
  if [[ -z "$free" ]]; then free="0"; fi
  printf 'CPU_CORES=%s\nAES_NI=%s\nRAM_KB=%s\nSWAP_KB=%s\nDISK_TYPE=%s\nDISK_FREE_KB=%s\n' \
    "$cores" "$aes" "$ram" "$swap" "$disk" "$free"
}
