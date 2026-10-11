#!/usr/bin/env bash
# Backup + atomic write. Every file is backed up before change with manifest.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_BACKUP_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_BACKUP_SOURCED=1

# new_backup_id -> prints timestamp-id
new_backup_id() {
  local ts
  ts="$(date -u '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%Y%m%d-%H%M%S')"
  printf '%s-%s\n' "$ts" "$$"
}

# backup_file <src> <backup_dir> — copies src, appends manifest line.
backup_file() {
  local src="$1" dest_dir="$2"
  local base
  base="$(basename "$src")"
  mkdir -p "$dest_dir" || return 1
  if [[ -e "$src" ]]; then
    cp -a "$src" "$dest_dir/$base" 2>/dev/null || cp "$src" "$dest_dir/$base" || return 1
    printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" "$src" "$dest_dir/$base" >>"$dest_dir/manifest.tsv"
  else
    printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" "$src" "(absent)" >>"$dest_dir/manifest.tsv"
  fi
}

# atomic_write <tmpfile> <dest> — validate hook optional via $3 (command).
atomic_write() {
  local tmp="$1" dest="$2"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir" || return 1
  chmod 0644 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$dest"
}
