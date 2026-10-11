#!/usr/bin/env bats
# backup/rollback: restore, partial failure, idempotent re-run.
# shellcheck shell=bash

load bats_helper

@test "rollback restores all files and reports counts" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w1\n' >"$SRV_TUNE_TMP/b.conf"
  d="$SRV_TUNE_STATE_DIR/backups/t1"
  backup_file "$SRV_TUNE_TMP/a.conf" "$d"
  backup_file "$SRV_TUNE_TMP/b.conf" "$d"
  printf 'v2\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w2\n' >"$SRV_TUNE_TMP/b.conf"
  run rollback_id "t1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 restored, 0 failed"* ]]
  [ "$(cat "$SRV_TUNE_TMP/a.conf")" = "v1" ]
  [ "$(cat "$SRV_TUNE_TMP/b.conf")" = "w1" ]
}

@test "rollback continues past a missing backup copy and fails loudly" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w1\n' >"$SRV_TUNE_TMP/b.conf"
  d="$SRV_TUNE_STATE_DIR/backups/t2"
  backup_file "$SRV_TUNE_TMP/a.conf" "$d"
  backup_file "$SRV_TUNE_TMP/b.conf" "$d"
  rm -f "$d/b.conf"
  printf 'v2\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w2\n' >"$SRV_TUNE_TMP/b.conf"
  run rollback_id "t2"
  [ "$status" -ne 0 ]
  # The intact entry is still restored despite the sibling failure.
  [ "$(cat "$SRV_TUNE_TMP/a.conf")" = "v1" ]
  [ "$(cat "$SRV_TUNE_TMP/b.conf")" = "w2" ]
  [[ "$output" == *"backup copy missing"* ]]
  [[ "$output" == *"1 restored, 1 failed"* ]]
}

@test "rollback re-run is idempotent" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$SRV_TUNE_TMP/a.conf"
  d="$SRV_TUNE_STATE_DIR/backups/t3"
  backup_file "$SRV_TUNE_TMP/a.conf" "$d"
  printf 'v2\n' >"$SRV_TUNE_TMP/a.conf"
  run rollback_id "t3"
  [ "$status" -eq 0 ]
  run rollback_id "t3"
  [ "$status" -eq 0 ]
  [ "$(cat "$SRV_TUNE_TMP/a.conf")" = "v1" ]
}

@test "rollback removes files that were absent at backup time" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  d="$SRV_TUNE_STATE_DIR/backups/t4"
  backup_file "$SRV_TUNE_TMP/new.conf" "$d"
  printf 'created-later\n' >"$SRV_TUNE_TMP/new.conf"
  run rollback_id "t4"
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_TMP/new.conf" ]
}

@test "rollback under caller set -e restores everything (no mid-loop abort)" {
  source "$SRV_TUNE_ROOT/lib/backup.sh"
  printf 'v1\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w1\n' >"$SRV_TUNE_TMP/b.conf"
  d="$SRV_TUNE_STATE_DIR/backups/t5"
  backup_file "$SRV_TUNE_TMP/a.conf" "$d"
  backup_file "$SRV_TUNE_TMP/b.conf" "$d"
  printf 'v2\n' >"$SRV_TUNE_TMP/a.conf"
  printf 'w2\n' >"$SRV_TUNE_TMP/b.conf"
  run env SRV_TUNE_STATE_DIR="$SRV_TUNE_STATE_DIR" SRV_TUNE_TMP="$SRV_TUNE_TMP" \
    bash -c 'set -euo pipefail; source "$1/backup.sh"; source "$1/rollback.sh"; rollback_id "t5"' bash "$SRV_TUNE_ROOT/lib"
  [ "$status" -eq 0 ]
  [ "$(cat "$SRV_TUNE_TMP/a.conf")" = "v1" ]
  [ "$(cat "$SRV_TUNE_TMP/b.conf")" = "w1" ]
}
