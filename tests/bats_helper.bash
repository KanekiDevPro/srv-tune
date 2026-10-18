#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared bats helpers.
# shellcheck shell=bash

bats_require_minimum_version 1.5.0

setup() {
  # Per-test isolation: BATS_TMPDIR can be shared (it is /tmp on some hosts),
  # so every test gets its own state/lock dir. teardown() removes it.
  export TEMPER_TEST=1
  TEMPER_TMP="$(mktemp -d "$BATS_TMPDIR/srv-XXXXXX")"
  export TEMPER_TMP
  export TEMPER_STATE_DIR="$TEMPER_TMP/state"
  export TEMPER_LOCK_FILE="$TEMPER_TMP/lock"
  export TEMPER_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TEMPER_STATE_DIR/backups"
}

teardown() {
  rm -rf "${TEMPER_TMP:-}" 2>/dev/null || true
}
