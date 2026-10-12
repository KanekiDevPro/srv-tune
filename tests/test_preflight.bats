#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Preflight tiers + dry-run contract placeholder.
# shellcheck shell=bash

load bats_helper

@test "preflight tier function exists and returns a tier" {
  source "$SRV_TUNE_ROOT/lib/preflight.sh"
  run preflight_os_tier
  [ "$status" -eq 0 ]
  [[ "$output" =~ tier1|tier2|best-effort|eol|unsupported ]]
}

@test "optimizer status exits 0" {
  run bash "$SRV_TUNE_ROOT/optimizer.sh" status
  [ "$status" -eq 0 ]
}
