#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Small portable utilities. No GNU-only flags.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_UTIL_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_UTIL_SOURCED=1

is_root() {
  [[ "${EUID:-$(id -u)}" == "0" ]]
}

# path_is_world_writable <dir> - portable other-write-bit check, no GNU stat.
path_is_world_writable() {
  local perms
  perms="$(ls -ld "$1" 2>/dev/null | awk '{print $1}')"
  case "$perms" in
  ????????w*) return 0 ;;
  *) return 1 ;;
  esac
}

# refuse_world_writable <dir> <what> - fails when root would use a
# world-writable path. Returns 0 when safe or non-root with explicit path.
refuse_world_writable() {
  local dir="$1" what="$2"
  if is_root && path_is_world_writable "$dir"; then
    printf 'error: refusing world-writable %s for root: %s\n' "$what" "$dir" >&2
    return 1
  fi
  return 0
}

# read_kv_file <file> <key> - portable KEY=VALUE reader, no PCRE.
# Prints the value (exit 0) or nothing (exit 1). Never aborts set -e callers
# on a missing key: grep-no-match is expected, not an error.
read_kv_file() {
  local file="$1" key="$2" val
  [[ -f "$file" ]] || return 1
  val="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
  [[ -n "$val" ]] || return 1
  printf '%s\n' "$val"
}

# json_escape - minimal escaper for strings we emit.
json_escape() {
  local s="$1"
  printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ' | tr '\t' ' '
}
# show_diff <old> <new> - unified diff, no color dependency.
show_diff() {
  if command -v diff >/dev/null 2>&1; then
    diff -u "$1" "$2" || true
  else
    printf '(diff not available)\n'
  fi
}
