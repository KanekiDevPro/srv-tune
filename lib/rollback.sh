#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rollback from manifest. rollback [id] | list-backups.
# Continues past per-file failures and reports them; exit 0 = fully restored,
# exit 1 = one or more entries failed (see stderr). Re-running is safe.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_ROLLBACK_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_ROLLBACK_SOURCED=1

rollback_list() {
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  if [[ ! -d "$base/backups" ]]; then
    printf 'no backups\n'
    return 0
  fi
  ls -1 "$base/backups" 2>/dev/null || printf 'no backups\n'
}

rollback_id() {
  local id="$1"
  local base="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  local dir="$base/backups/$id"
  if [[ -z "$id" ]]; then
    printf 'error: rollback requires an id (see list-backups)\n' >&2
    return 1
  fi
  if [[ ! -f "$dir/manifest.tsv" ]]; then
    printf 'error: backup not found: %s\n' "$id" >&2
    return 1
  fi
  # if-form throughout: a skipped entry must not abort set -e callers.
  local _ts src bak ok fail
  ok=0
  fail=0
  while IFS="$(printf '\t')" read -r _ts src bak; do
    if [[ -z "$src" ]]; then
      continue
    fi
    if [[ "$bak" == "(absent)" ]]; then
      if rm -f "$src" 2>/dev/null; then
        printf 'removed %s (was absent)\n' "$src"
        ok=$((ok + 1))
      else
        printf 'error: cannot remove %s\n' "$src" >&2
        fail=$((fail + 1))
      fi
    elif [[ -f "$bak" ]]; then
      if mkdir -p "$(dirname "$src")" 2>/dev/null && { cp -a "$bak" "$src" 2>/dev/null || cp "$bak" "$src" 2>/dev/null; }; then
        printf 'restored %s\n' "$src"
        ok=$((ok + 1))
      else
        printf 'error: cannot restore %s\n' "$src" >&2
        fail=$((fail + 1))
      fi
    else
      printf 'error: backup copy missing for %s (expected %s)\n' "$src" "$bak" >&2
      fail=$((fail + 1))
    fi
  done <"$dir/manifest.tsv"
  printf 'rollback %s: %s restored, %s failed\n' "$id" "$ok" "$fail"
  if [[ "$fail" -gt 0 ]]; then
    return 1
  fi
  return 0
}
