#!/usr/bin/env bash
# State directories and applied-changes log.
# No silent fallbacks: TMPDIR is TEST-only (SRV_TUNE_TEST=1). Root never uses
# world-writable state paths.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_STATE_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_STATE_SOURCED=1

# state_effective_dir - prints the state dir, applying the TEST-only rule.
state_effective_dir() {
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  if [[ -d "$base" ]] && [[ -w "$base" ]]; then
    printf '%s\n' "$base"
    return 0
  fi
  if mkdir -p "$base" 2>/dev/null; then
    printf '%s\n' "$base"
    return 0
  fi
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]]; then
    base="${TMPDIR:-/tmp}/srv-tune-test-$(id -u 2>/dev/null || printf 'x')"
    mkdir -p "$base" 2>/dev/null || return 1
    printf '%s\n' "$base"
    return 0
  fi
  printf 'error: state dir %s is not writable.\n' "$base" >&2
  printf 'error: run as root, or set SRV_TUNE_STATE_DIR to a writable path.\n' >&2
  printf 'error: TMPDIR fallback is TEST-only (SRV_TUNE_TEST=1).\n' >&2
  return 1
}

state_init() {
  local base
  base="$(state_effective_dir)" || return 1
  export SRV_TUNE_STATE_DIR="$base"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
  refuse_world_writable "$base" "state dir" || return 1
  mkdir -p "$base/backups" "$base/guard" 2>/dev/null || return 1
  touch "$base/applied-changes.log" 2>/dev/null || return 1
}

state_log_applied() {
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%FT%T%Z')" "$*" >>"$base/applied-changes.log"
}
