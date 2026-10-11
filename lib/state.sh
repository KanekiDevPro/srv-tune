#!/usr/bin/env bash
# State directories and applied-changes log.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_STATE_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_STATE_SOURCED=1

state_init() {
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  mkdir -p "$base/backups" "$base/guard" 2>/dev/null || return 1
  touch "$base/applied-changes.log" 2>/dev/null || return 1
}

state_log_applied() {
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%FT%T%Z')" "$*" >>"$base/applied-changes.log"
}
