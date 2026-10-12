#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# OS collector (read-only).
# shellcheck shell=bash

collect_os() {
  local f="${OS_RELEASE_FILE:-/etc/os-release}"
  local id="unknown" ver="unknown"
  if [[ -f "$f" ]]; then
    # || true: absent keys are not errors (grep-no-match under pipefail).
    id="$(grep -E '^ID=' "$f" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '"' || true)"
    ver="$(grep -E '^VERSION_ID=' "$f" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '"' || true)"
  fi
  if [[ -z "$id" ]]; then id="unknown"; fi
  if [[ -z "$ver" ]]; then ver="unknown"; fi
  local kernel="unknown" init="unknown" virt="unknown" cloud="no"
  kernel="$(uname -r 2>/dev/null || printf 'unknown')"
  if [[ -d /run/systemd/system ]]; then
    init="systemd"
  elif command -v openrc-run >/dev/null 2>&1; then
    init="openrc"
  fi
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt 2>/dev/null || printf 'bare')"
  elif [[ -f /.dockerenv ]]; then
    virt="docker"
  fi
  if [[ -f /etc/cloud/cloud.cfg ]] || [[ -d /var/lib/cloud ]]; then
    cloud="yes"
  fi
  printf 'OS_ID=%s\nOS_VERSION=%s\nKERNEL=%s\nINIT=%s\nVIRT=%s\nCLOUD_INIT=%s\n' \
    "$id" "$ver" "$kernel" "$init" "$virt" "$cloud"
}
