#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Lock to prevent concurrent runs. flock if present, else mkdir fallback.
# No silent fallbacks: TMPDIR is TEST-only (SRV_TUNE_TEST=1). In normal mode
# a missing /run fails with a clear error. Root never uses world-writable
# lock paths.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_LOCK_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_LOCK_SOURCED=1

SRV_TUNE_LOCK_FD=""

# lock_effective_file - prints the lock path, applying the TEST-only rule.
lock_effective_file() {
  local lock_file="${SRV_TUNE_LOCK_FILE:-/run/srv-tune.lock}"
  local parent
  parent="$(dirname "$lock_file")"
  if [[ -d "$parent" ]] && [[ -w "$parent" ]]; then
    printf '%s\n' "$lock_file"
    return 0
  fi
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]]; then
    local fallback
    fallback="${TMPDIR:-/tmp}/srv-tune-test-$(id -u 2>/dev/null || printf 'x')"
    mkdir -p "$fallback" 2>/dev/null || return 1
    # Root-safe (see state.sh): the dir itself must not be world-writable.
    chmod 700 "$fallback" 2>/dev/null || true
    printf '%s/srv-tune-test-%s.lock\n' "$fallback" "$(id -u 2>/dev/null || printf 'x')"
    return 0
  fi
  printf 'error: lock dir %s is missing or unwritable.\n' "$parent" >&2
  printf 'error: run as root, or set SRV_TUNE_LOCK_FILE to a writable path.\n' >&2
  printf 'error: TMPDIR fallback is TEST-only (SRV_TUNE_TEST=1).\n' >&2
  return 1
}

lock_acquire() {
  local lock_file
  lock_file="$(lock_effective_file)" || return 1
  export SRV_TUNE_LOCK_FILE="$lock_file"
  local parent
  parent="$(dirname "$lock_file")"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
  refuse_world_writable "$parent" "lock dir" || return 1
  mkdir -p "$parent" 2>/dev/null || true
  local lock_dir="${lock_file}.d"
  # Backend override (tests, flock-less containers). Default: auto.
  if [[ "${SRV_TUNE_LOCK_BACKEND:-auto}" != "mkdir" ]] && command -v flock >/dev/null 2>&1; then
    # Probe with a NON-special builtin first: redirection failure on `exec`
    # (special builtin) would kill the shell AND any 2>/dev/null here would
    # permanently redirect this shell's own stderr to null. Never attach
    # stderr redirections to bare exec.
    if ! printf '' >>"$lock_file" 2>/dev/null; then
      printf 'error: cannot write lock file %s\n' "$lock_file" >&2
      return 1
    fi
    exec 9>"$lock_file"
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
    exec 9>&-
    SRV_TUNE_LOCK_FD=""
  fi
  rmdir "${lock_file}.d" 2>/dev/null || true
}
