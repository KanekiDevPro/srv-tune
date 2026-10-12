#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Backup/rollback + idempotency.
# shellcheck shell=bash

load bats_helper

@test "backup and rollback restores file" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  f="$BATS_TMPDIR/orig.conf"
  printf 'v1\n' >"$f"
  d="$SRV_TUNE_STATE_DIR/backups/t1"
  backup_file "$f" "$d"
  printf 'v2\n' >"$f"
  rollback_id "t1"
  [ "$(cat "$f")" = "v1" ]
}

@test "atomic_write moves temp into place" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  t="$BATS_TMPDIR/new.tmp"
  d="$BATS_TMPDIR/dest.conf"
  printf 'hello\n' >"$t"
  atomic_write "$t" "$d"
  [ "$(cat "$d")" = "hello" ]
}

@test "rollback list works empty" {
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  run rollback_list
  [ "$status" -eq 0 ]
}
