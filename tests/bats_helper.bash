#!/usr/bin/env bash
# Shared bats helpers.
# shellcheck shell=bash

bats_require_minimum_version 1.5.0

setup() {
  # Per-test isolation: BATS_TMPDIR can be shared (it is /tmp on some hosts),
  # so every test gets its own state/lock dir. teardown() removes it.
  export SRV_TUNE_TEST=1
  SRV_TUNE_TMP="$(mktemp -d "$BATS_TMPDIR/srv-XXXXXX")"
  export SRV_TUNE_TMP
  export SRV_TUNE_STATE_DIR="$SRV_TUNE_TMP/state"
  export SRV_TUNE_LOCK_FILE="$SRV_TUNE_TMP/lock"
  export SRV_TUNE_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$SRV_TUNE_STATE_DIR/backups"
}

teardown() {
  rm -rf "${SRV_TUNE_TMP:-}" 2>/dev/null || true
}
