#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# dry-run (exact diff + reason) and safe apply shared by all P3 modules.
# Nothing here touches the system when DRY_RUN=1: apply_file prints the diff
# and returns 0 without writing.
# shellcheck shell=bash

if [[ -n "${__TEMPER_DRYRUN_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_DRYRUN_SOURCED=1

# dry_run_file <path> <new_tmp> <why> - unified diff old-vs-new + one why line.
dry_run_file() {
  local path="$1" new_tmp="$2" why="$3"
  printf '%s\n' "--- $path (current)"
  printf '%s\n' "+++ $path (proposed)"
  if [[ -f "$path" ]]; then
    diff -u "$path" "$new_tmp" 2>/dev/null || true
  else
    printf '(new file; %s lines proposed)\n' "$(wc -l <"$new_tmp" | tr -d ' ')"
    cat "$new_tmp"
  fi
  printf 'why: %s\n' "$why"
}

# apply_file <backup_dir> <path> <new_tmp> <why> [validate_cmd...]
# backup -> atomic write -> optional validate -> restore+fail on invalid.
apply_file() {
  local backup_dir="$1" path="$2" new_tmp="$3" why="$4"
  shift 4
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/backup.sh"
  if [[ "${TEMPER_DRY_RUN:-0}" == "1" ]]; then
    dry_run_file "$path" "$new_tmp" "$why"
    return 0
  fi
  backup_file "$path" "$backup_dir" || return 1
  atomic_write "$new_tmp" "$path" || return 1
  if [[ $# -gt 0 ]]; then
    if ! "$@" >/dev/null 2>&1; then
      printf 'error: validation failed for %s; restoring\n' "$path" >&2
      local base
      base="$(basename "$path")"
      if [[ -f "$backup_dir/$base" ]]; then
        cp -a "$backup_dir/$base" "$path" 2>/dev/null || cp "$backup_dir/$base" "$path" || true
      else
        rm -f "$path"
      fi
      return 1
    fi
  fi
  printf 'applied %s (%s)\n' "$path" "$why"
}
