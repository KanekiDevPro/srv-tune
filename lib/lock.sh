#!/usr/bin/env bash
# Lock to prevent concurrent runs. flock if present, else mkdir fallback.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_LOCK_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_LOCK_SOURCED=1

SRV_TUNE_LOCK_FD=""

lock_acquire() {
  local lock_file="${SRV_TUNE_LOCK_FILE:-/run/srv-tune.lock}"
  # Fall back when /run is missing or unwritable (containers, test envs).
  if [[ "$lock_file" == "/run/"* ]] && ! mkdir -p "/run" 2>/dev/null; then
    lock_file="${TMPDIR:-/tmp}/srv-tune.lock"
    export SRV_TUNE_LOCK_FILE="$lock_file"
  fi
  mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
  local lock_dir="${lock_file}.d"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock_file" 2>/dev/null || return 1
    if ! flock -n 9; then
      printf 'error: another srv-tune run is active (%s)\n' "$lock_file" >&2
      return 1
    fi
    SRV_TUNE_LOCK_FD="9"
    return 0
  fi
  if mkdir "$lock_dir" 2>/dev/null; then
    return 0
  fi
  if [[ -d "$lock_dir" ]]; then
    printf 'error: another srv-tune run is active (%s)\n' "$lock_dir" >&2
    return 1
  fi
  printf 'error: cannot create lock dir %s\n' "$lock_dir" >&2
  return 1
}

lock_release() {
  local lock_file="${SRV_TUNE_LOCK_FILE:-/run/srv-tune.lock}"
  if [[ -n "$SRV_TUNE_LOCK_FD" ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    SRV_TUNE_LOCK_FD=""
  fi
  rmdir "${lock_file}.d" 2>/dev/null || true
}
