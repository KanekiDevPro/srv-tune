#!/usr/bin/env bash
# Shared bats helpers.
# shellcheck shell=bash

setup() {
  export SRV_TUNE_STATE_DIR="$BATS_TMPDIR/state"
  export SRV_TUNE_LOCK_FILE="$BATS_TMPDIR/lock"
  export SRV_TUNE_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$SRV_TUNE_STATE_DIR/backups"
}
