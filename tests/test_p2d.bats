#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# P2d: dry-run diff output, safe apply, health checks, preflight tiers.
# NOTE: bats `run` executes external commands only, so lib functions always
# run inside `bash -c 'source ...; func ...'` wrappers (never `run func`).
# shellcheck shell=bash

load bats_helper

@test "dry_run_file prints unified diff plus why line, writes nothing" {
  printf 'a=1\n' >"$TEMPER_TMP/old.conf"
  printf 'a=2\n' >"$TEMPER_TMP/new.conf"
  run env TEMPER_DRY_RUN=1 bash -c 'source "$1"; dry_run_file "$2" "$3" "$4"' \
    bash "$TEMPER_ROOT/lib/dryrun.sh" "$TEMPER_TMP/old.conf" "$TEMPER_TMP/new.conf" "computed from 8GB RAM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-a=1"* ]]
  [[ "$output" == *"+a=2"* ]]
  [[ "$output" == *"why: computed from 8GB RAM"* ]]
  [ "$(cat "$TEMPER_TMP/old.conf")" = "a=1" ]
}

@test "apply_file dry-run writes nothing" {
  printf 'a=1\n' >"$TEMPER_TMP/old.conf"
  printf 'a=2\n' >"$TEMPER_TMP/new.conf"
  run env TEMPER_DRY_RUN=1 bash -c 'source "$1"; apply_file "$2" "$3" "$4" "$5"' \
    bash "$TEMPER_ROOT/lib/dryrun.sh" "$TEMPER_STATE_DIR/backups/d1" "$TEMPER_TMP/old.conf" "$TEMPER_TMP/new.conf" "test why"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMPER_TMP/old.conf")" = "a=1" ]
  [ ! -d "$TEMPER_STATE_DIR/backups/d1" ]
}

@test "apply_file writes, validates, and restores on invalid" {
  printf 'a=1\n' >"$TEMPER_TMP/old.conf"
  printf 'a=2\n' >"$TEMPER_TMP/good.conf"
  printf 'a=3\n' >"$TEMPER_TMP/bad.conf"
  run env TEMPER_DRY_RUN=0 bash -c 'source "$1"; apply_file "$2" "$3" "$4" "$5" true' \
    bash "$TEMPER_ROOT/lib/dryrun.sh" "$TEMPER_STATE_DIR/backups/d2" "$TEMPER_TMP/old.conf" "$TEMPER_TMP/good.conf" "good"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMPER_TMP/old.conf")" = "a=2" ]
  run env TEMPER_DRY_RUN=0 bash -c 'source "$1"; apply_file "$2" "$3" "$4" "$5" false' \
    bash "$TEMPER_ROOT/lib/dryrun.sh" "$TEMPER_STATE_DIR/backups/d3" "$TEMPER_TMP/old.conf" "$TEMPER_TMP/bad.conf" "bad"
  [ "$status" -ne 0 ]
  [ "$(cat "$TEMPER_TMP/old.conf")" = "a=2" ]
}

@test "health_dns passes for localhost" {
  if ! command -v getent >/dev/null 2>&1; then
    skip "getent missing on this host"
  fi
  run bash -c 'source "$1"; health_dns localhost' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -eq 0 ]
}

@test "health_dns fails for a guaranteed-absent name" {
  if ! command -v getent >/dev/null 2>&1; then
    skip "getent missing on this host"
  fi
  run bash -c 'source "$1"; health_dns invalid-hostname-temper.invalid' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -ne 0 ]
}

@test "health_sshd skips cleanly when sshd is missing" {
  if command -v sshd >/dev/null 2>&1; then
    skip "sshd present; covered on Linux CI"
  fi
  run bash -c 'source "$1"; health_sshd' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -eq 2 ]
}

@test "health_port skips cleanly when ss is missing" {
  if command -v ss >/dev/null 2>&1; then
    skip "ss present; covered on Linux CI"
  fi
  run bash -c 'source "$1"; health_port 22' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -eq 2 ]
}

@test "health_ssh_owner prints one of socket|service|none" {
  run bash -c 'source "$1"; health_ssh_owner' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -eq 0 ]
  case "$output" in
  socket | service | none) ;;
  *) return 1 ;;
  esac
}

@test "health_mirror_uri accepts a file URI and rejects a dead one" {
  if ! command -v curl >/dev/null 2>&1; then
    skip "curl missing on this host"
  fi
  printf 'x' >"$TEMPER_TMP/f"
  # Windows-native curl cannot resolve MSYS /tmp paths: probe first.
  if bash -c 'source "$1"; health_mirror_uri "$2"' bash "$TEMPER_ROOT/lib/health.sh" "file://$TEMPER_TMP/f"; then
    run bash -c 'source "$1"; health_mirror_uri "$2"' bash "$TEMPER_ROOT/lib/health.sh" "file://$TEMPER_TMP/f"
    [ "$status" -eq 0 ]
  else
    skip "host curl cannot open file:// URIs; covered on Linux CI"
  fi
  run bash -c 'source "$1"; health_mirror_uri "http://127.0.0.1:9/nope"' bash "$TEMPER_ROOT/lib/health.sh"
  [ "$status" -ne 0 ]
}

@test "preflight: EOL and unsupported tiers return 2" {
  printf 'ID=debian\nVERSION_ID=11\n' >"$TEMPER_TMP/os11"
  run env OS_RELEASE_FILE="$TEMPER_TMP/os11" bash -c 'source "$1"; preflight_check' bash "$TEMPER_ROOT/lib/preflight.sh"
  [ "$status" -eq 2 ]
  printf 'ID=arch\nVERSION_ID=rolling\n' >"$TEMPER_TMP/osarch"
  run env OS_RELEASE_FILE="$TEMPER_TMP/osarch" bash -c 'source "$1"; preflight_check' bash "$TEMPER_ROOT/lib/preflight.sh"
  [ "$status" -eq 2 ]
}

@test "preflight: tier1 passes disk check on this host" {
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$TEMPER_TMP/os2404"
  run env OS_RELEASE_FILE="$TEMPER_TMP/os2404" bash -c 'source "$1"; preflight_check' bash "$TEMPER_ROOT/lib/preflight.sh"
  [ "$status" -eq 0 ]
}

@test "audit is read-only: profile printed, state dir untouched" {
  run bash "$TEMPER_ROOT/optimizer.sh" audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:"* ]]
  [ -z "$(ls -A "$TEMPER_STATE_DIR/backups" 2>/dev/null)" ]
  [ -z "$(ls -A "$TEMPER_STATE_DIR/guard" 2>/dev/null)" ]
}
