#!/usr/bin/env bats
# Scanner: read-only, JSON valid, score 0-100, profile present.
# shellcheck shell=bash

load bats_helper

@test "scan exits 0 and prints score" {
  run bash "$SRV_TUNE_ROOT/scanner/scan.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recommended profile:"* ]]
}

@test "scan --recommend-only prints profile" {
  run bash "$SRV_TUNE_ROOT/scanner/scan.sh" --recommend-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile:"* ]]
}

@test "scan writes JSON file when asked" {
  out="$BATS_TMPDIR/scan.json"
  SRV_TUNE_JSON_OUT="$out" run bash "$SRV_TUNE_ROOT/scanner/scan.sh"
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q '"SCORE"' "$out"
  grep -q '"PROFILE"' "$out"
}
