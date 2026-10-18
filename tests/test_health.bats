#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# health command: read-only drift check (state dir, guards, module verify
# replay, --json report).
# shellcheck shell=bash

load bats_helper

_health_env() {
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  mkdir -p "$TEMPER_TMP/proc/sys/fs" "$TEMPER_SYSROOT"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf '1048576\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
}

@test "health: fresh state passes and notes no applied changes" {
  run bash "$TEMPER_ROOT/optimizer.sh" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"no applied changes"* ]]
  [[ "$output" == *"PASS state-dir"* ]]
  [[ "$output" == *"PASS guards"* ]]
}

@test "health: verified module replays PASS" {
  _health_env
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/lib/modules.sh"
  module_load limits
  d="$TEMPER_STATE_DIR/backups/h1"
  mkdir -p "$d"
  limits_apply "$d"
  printf '2026-10-17T00:00:00Z module=limits backup=h1\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS module:limits"* ]]
}

@test "health: drifted module FAILs and exits 1" {
  _health_env
  printf '2026-10-17T00:00:00Z module=limits backup=h2\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL module:limits"* ]]
  [[ "$output" == *"drop-in missing"* ]]
}

@test "health: unresolved guard is reported" {
  mkdir -p "$TEMPER_STATE_DIR/guard"
  : >"$TEMPER_STATE_DIR/guard/revert-g1.sh"
  run bash "$TEMPER_ROOT/optimizer.sh" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"guard:g1"* ]]
}

@test "health: confirmed guard is not flagged" {
  mkdir -p "$TEMPER_STATE_DIR/guard"
  : >"$TEMPER_STATE_DIR/guard/revert-g2.sh"
  : >"$TEMPER_STATE_DIR/guard/cancelled-g2"
  run bash "$TEMPER_ROOT/optimizer.sh" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS guards"* ]]
  [[ "$output" != *"guard:g2"* ]]
}

@test "health: --json writes a report" {
  run bash "$TEMPER_ROOT/optimizer.sh" health --json "$TEMPER_TMP/health.json"
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_TMP/health.json" ]
  run grep -q '"checks"' "$TEMPER_TMP/health.json"
  [ "$status" -eq 0 ]
  run grep -q '"status":"pass"' "$TEMPER_TMP/health.json"
  [ "$status" -eq 0 ]
}
