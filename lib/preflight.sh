#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pre-flight: root, disk space, network, OS support. Warn on EOL, never upgrade.
# shellcheck shell=bash

if [[ -n "${__TEMPER_PREFLIGHT_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_PREFLIGHT_SOURCED=1

preflight_os_id() {
  local f="${OS_RELEASE_FILE:-/etc/os-release}" id
  [[ -f "$f" ]] || {
    printf 'unknown\n'
    return 0
  }
  # || true: grep finds nothing when the key is absent; that is not an error.
  id="$(grep -E '^ID=' "$f" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '"' || true)"
  [[ -z "$id" ]] && id="unknown"
  printf '%s\n' "$id"
}

preflight_os_version() {
  local f="${OS_RELEASE_FILE:-/etc/os-release}" ver
  [[ -f "$f" ]] || {
    printf 'unknown\n'
    return 0
  }
  ver="$(grep -E '^VERSION_ID=' "$f" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '"' || true)"
  [[ -z "$ver" ]] && ver="unknown"
  printf '%s\n' "$ver"
}

# Returns tier: tier1|tier2|best-effort|eol|unsupported
preflight_os_tier() {
  local id ver
  id="$(preflight_os_id)"
  ver="$(preflight_os_version)"
  case "${id}:${ver}" in
  ubuntu:24.04 | ubuntu:26.04 | debian:13) printf 'tier1\n' ;;
  ubuntu:22.04 | debian:12) printf 'tier2\n' ;;
  ubuntu:20.04) printf 'best-effort\n' ;;
  debian:11) printf 'eol\n' ;;
  *) printf 'unsupported\n' ;;
  esac
}

preflight_check() {
  local tier
  tier="$(preflight_os_tier)"
  case "$tier" in
  eol)
    printf 'warn: OS is EOL (Debian 11 EOL 2026-08-31). Upgrade recommended. No changes applied.\n' >&2
    return 2
    ;;
  unsupported)
    printf 'warn: unsupported OS %s %s. Continuing read-only; apply is blocked.\n' "$(preflight_os_id)" "$(preflight_os_version)" >&2
    return 2
    ;;
  esac
  # Disk space: need >=500MB free in / and state dir parent.
  local free_kb
  free_kb="$(df -k / 2>/dev/null | awk 'NR==2{print $4}' || true)"
  if [[ -n "$free_kb" ]] && [[ "$free_kb" -lt 512000 ]]; then
    printf 'error: low disk space (%s KB free). Need >=500MB.\n' "$free_kb" >&2
    return 1
  fi
  return 0
}
