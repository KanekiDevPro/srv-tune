#!/usr/bin/env bash
# Rollback from manifest. rollback [id] | list-backups.
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
  local ts src bak
  while IFS="$(printf '\t')" read -r ts src bak; do
    [[ -z "$src" ]] && continue
    if [[ "$bak" == "(absent)" ]]; then
      rm -f "$src"
      printf 'removed %s (was absent)\n' "$src"
    elif [[ -f "$bak" ]]; then
      mkdir -p "$(dirname "$src")"
      cp -a "$bak" "$src" 2>/dev/null || cp "$bak" "$src"
      printf 'restored %s\n' "$src"
    fi
  done <"$dir/manifest.tsv"
}
