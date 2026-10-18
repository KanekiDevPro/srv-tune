#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared constants and strict-mode helpers for temper.
# shellcheck shell=bash

set -euo pipefail

if [[ -n "${__TEMPER_COMMON_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_COMMON_SOURCED=1

TEMPER_NAME="temper"
TEMPER_VERSION="$(cat "${TEMPER_ROOT:-.}/VERSION" 2>/dev/null || echo "0.1.0")"
export TEMPER_NAME TEMPER_VERSION
readonly TEMPER_NAME TEMPER_VERSION

: "${TEMPER_STATE_DIR:=/var/lib/temper}"
: "${TEMPER_LOCK_FILE:=/run/temper.lock}"
: "${TEMPER_LANG:=en}"
export TEMPER_STATE_DIR TEMPER_LOCK_FILE TEMPER_LANG

temper_root() {
  local src="${BASH_SOURCE[0]:-$0}"
  local dir
  dir="$(cd "$(dirname "$src")/.." && pwd)"
  printf '%s\n' "$dir"
}

# Portable command check (no GNU-only flags).
temper_has() {
  command -v "$1" >/dev/null 2>&1
}

temper_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

temper_warn() {
  printf 'warn: %s\n' "$*" >&2
}
