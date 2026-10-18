#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# backup/rollback: restore, partial failure, idempotent re-run.
# shellcheck shell=bash

load bats_helper

@test "rollback restores all files and reports counts" {
  source "$TEMPER_ROOT/lib/backup.sh"
  source "$TEMPER_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$TEMPER_TMP/a.conf"
  printf 'w1\n' >"$TEMPER_TMP/b.conf"
  d="$TEMPER_STATE_DIR/backups/t1"
  backup_file "$TEMPER_TMP/a.conf" "$d"
  backup_file "$TEMPER_TMP/b.conf" "$d"
  printf 'v2\n' >"$TEMPER_TMP/a.conf"
  printf 'w2\n' >"$TEMPER_TMP/b.conf"
  run rollback_id "t1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 restored, 0 failed"* ]]
  [ "$(cat "$TEMPER_TMP/a.conf")" = "v1" ]
  [ "$(cat "$TEMPER_TMP/b.conf")" = "w1" ]
}

@test "rollback continues past a missing backup copy and fails loudly" {
  source "$TEMPER_ROOT/lib/backup.sh"
  source "$TEMPER_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$TEMPER_TMP/a.conf"
  printf 'w1\n' >"$TEMPER_TMP/b.conf"
  d="$TEMPER_STATE_DIR/backups/t2"
  backup_file "$TEMPER_TMP/a.conf" "$d"
  backup_file "$TEMPER_TMP/b.conf" "$d"
  rm -f "$d/b.conf"
  printf 'v2\n' >"$TEMPER_TMP/a.conf"
  printf 'w2\n' >"$TEMPER_TMP/b.conf"
  run rollback_id "t2"
  [ "$status" -ne 0 ]
  # The intact entry is still restored despite the sibling failure.
  [ "$(cat "$TEMPER_TMP/a.conf")" = "v1" ]
  [ "$(cat "$TEMPER_TMP/b.conf")" = "w2" ]
  [[ "$output" == *"backup copy missing"* ]]
  [[ "$output" == *"1 restored, 1 failed"* ]]
}

@test "rollback re-run is idempotent" {
  source "$TEMPER_ROOT/lib/backup.sh"
  source "$TEMPER_ROOT/lib/rollback.sh"
  printf 'v1\n' >"$TEMPER_TMP/a.conf"
  d="$TEMPER_STATE_DIR/backups/t3"
  backup_file "$TEMPER_TMP/a.conf" "$d"
  printf 'v2\n' >"$TEMPER_TMP/a.conf"
  run rollback_id "t3"
  [ "$status" -eq 0 ]
  run rollback_id "t3"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMPER_TMP/a.conf")" = "v1" ]
}

@test "rollback removes files that were absent at backup time" {
  source "$TEMPER_ROOT/lib/backup.sh"
  source "$TEMPER_ROOT/lib/rollback.sh"
  d="$TEMPER_STATE_DIR/backups/t4"
  backup_file "$TEMPER_TMP/new.conf" "$d"
  printf 'created-later\n' >"$TEMPER_TMP/new.conf"
  run rollback_id "t4"
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_TMP/new.conf" ]
}

@test "rollback under caller set -e restores everything (no mid-loop abort)" {
  source "$TEMPER_ROOT/lib/backup.sh"
  printf 'v1\n' >"$TEMPER_TMP/a.conf"
  printf 'w1\n' >"$TEMPER_TMP/b.conf"
  d="$TEMPER_STATE_DIR/backups/t5"
  backup_file "$TEMPER_TMP/a.conf" "$d"
  backup_file "$TEMPER_TMP/b.conf" "$d"
  printf 'v2\n' >"$TEMPER_TMP/a.conf"
  printf 'w2\n' >"$TEMPER_TMP/b.conf"
  run env TEMPER_STATE_DIR="$TEMPER_STATE_DIR" TEMPER_TMP="$TEMPER_TMP" \
    bash -c 'set -euo pipefail; source "$1/backup.sh"; source "$1/rollback.sh"; rollback_id "t5"' bash "$TEMPER_ROOT/lib"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMPER_TMP/a.conf")" = "v1" ]
  [ "$(cat "$TEMPER_TMP/b.conf")" = "w1" ]
}
