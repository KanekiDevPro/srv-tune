#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# repair command: health replay -> re-apply ONLY drifted modules with the
# recorded profile; gates, dry-run, profile records. Sandboxed (SYSROOT).
# shellcheck shell=bash

load bats_helper

_repair_setup() {
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  export OS_RELEASE_FILE="$TEMPER_TMP/os-release"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$TEMPER_TMP/os-release"
  mkdir -p "$TEMPER_TMP/proc/sys/fs"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf '1048576\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
}

@test "repair: fresh state reports nothing to repair" {
  _repair_setup
  run bash "$TEMPER_ROOT/optimizer.sh" repair
  [ "$status" -eq 0 ]
  [[ "$output" == *"repair: nothing to repair"* ]]
  [[ "$output" == *"no applied changes"* ]]
}

@test "repair: drift with --dry-run prints the plan and writes nothing" {
  _repair_setup
  printf '2026-10-17T00:00:00Z module=limits backup=h1 profile=generic\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" repair --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAIL module:limits"* ]]
  [[ "$output" == *"repair plan: profile=generic modules=limits"* ]]
  [[ "$output" == *"dry-run"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "repair: drifted module is re-applied and logged with its profile" {
  _repair_setup
  printf '2026-10-17T00:00:00Z module=limits backup=h1 profile=generic\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" repair --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"repair plan: profile=generic modules=limits"* ]]
  [[ "$output" == *"ok: limits applied"* ]]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
  [ "$(wc -l <"$TEMPER_STATE_DIR/applied-changes.log")" -eq 2 ]
  grep -q "module=limits backup=.* profile=generic" "$TEMPER_STATE_DIR/applied-changes.log"
}

@test "repair: log line without a profile record exits 2" {
  _repair_setup
  printf '2026-10-17T00:00:00Z module=limits backup=h2\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" repair --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"no recorded profile for module limits"* ]]
}

@test "repair: mixed recorded profiles exit 2" {
  _repair_setup
  {
    printf '2026-10-17T00:00:00Z module=limits backup=h1 profile=web\n'
    printf '2026-10-17T00:00:01Z module=network backup=h2 profile=generic\n'
  } >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" repair --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"different profiles"* ]]
}

@test "repair: gated module without its flag is refused, not applied" {
  _repair_setup
  printf '2026-10-17T00:00:00Z module=ssh backup=h3 profile=generic\n' >"$TEMPER_STATE_DIR/applied-changes.log"
  run bash "$TEMPER_ROOT/optimizer.sh" repair --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL module:ssh"* ]]
  [[ "$output" == *"repair: ssh needs --with-ssh"* ]]
  [[ "$output" == *"nothing repairable"* ]]
}

@test "repair: non-root without a sandbox refuses" {
  if [[ "$(id -u)" -eq 0 ]]; then
    skip "running as root"
  fi
  run bash "$TEMPER_ROOT/optimizer.sh" repair
  [ "$status" -eq 2 ]
  [[ "$output" == *"repair needs root"* ]]
}

@test "repair: --json writes the pre-repair health report" {
  _repair_setup
  run bash "$TEMPER_ROOT/optimizer.sh" repair --json "$TEMPER_TMP/repair.json"
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_TMP/repair.json" ]
  grep -q '"checks"' "$TEMPER_TMP/repair.json"
}
