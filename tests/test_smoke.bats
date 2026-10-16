#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# VM smoke harness: only the SAFE paths run here (refusals, helpers).
# Live scenarios need a human-provided disposable VM alias; never localhost.
# shellcheck shell=bash

load bats_helper

@test "run-all refuses missing args" {
  run bash "$SRV_TUNE_ROOT/tests/vm/run-all.sh"
  [ "$status" -eq 2 ]
}

@test "run-all refuses localhost" {
  run bash "$SRV_TUNE_ROOT/tests/vm/run-all.sh" localhost ubuntu-24.04
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
}

@test "run-all refuses loopback" {
  run bash "$SRV_TUNE_ROOT/tests/vm/run-all.sh" 127.0.0.1 debian-13
  [ "$status" -ne 0 ]
}

@test "smoke-lib helpers are sourceable and safe" {
  export SMOKE_ALIAS=unused SMOKE_LOG="$SRV_TUNE_TMP/smoke.log"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/tests/vm/smoke-lib.sh"
  run human_only "reboot persistence" "step one" "step two"
  [ "$status" -eq 0 ]
  grep -q "HUMAN-ONLY" "$SRV_TUNE_TMP/smoke.log"
  grep -q "HUMAN STEP: step one" "$SRV_TUNE_TMP/smoke.log"
}

@test "rv_run reports SSH loss instead of hanging" {
  export SMOKE_ALIAS=invalid-host-srv-tune.invalid SMOKE_LOG="$SRV_TUNE_TMP/smoke2.log"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/tests/vm/smoke-lib.sh"
  if ! command -v ssh >/dev/null 2>&1; then
    skip "ssh client missing on this host"
  fi
  run rv_run "echo hi"
  [ "$status" -eq 3 ]
  [[ "$output" == *"SSH LOST"* ]]
}
