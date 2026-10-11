#!/usr/bin/env bash
# Shared constants and strict-mode helpers for srv-tune.
# shellcheck shell=bash

set -euo pipefail

if [[ -n "${__SRV_TUNE_COMMON_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_COMMON_SOURCED=1

SRV_TUNE_NAME="srv-tune"
SRV_TUNE_VERSION="$(cat "${SRV_TUNE_ROOT:-.}/VERSION" 2>/dev/null || echo "0.1.0")"
export SRV_TUNE_NAME SRV_TUNE_VERSION
readonly SRV_TUNE_NAME SRV_TUNE_VERSION

: "${SRV_TUNE_STATE_DIR:=/var/lib/srv-tune}"
: "${SRV_TUNE_LOCK_FILE:=/run/srv-tune.lock}"
: "${SRV_TUNE_LANG:=en}"
export SRV_TUNE_STATE_DIR SRV_TUNE_LOCK_FILE SRV_TUNE_LANG

srv_tune_root() {
  local src="${BASH_SOURCE[0]:-$0}"
  local dir
  dir="$(cd "$(dirname "$src")/.." && pwd)"
  printf '%s\n' "$dir"
}

# Portable command check (no GNU-only flags).
srv_tune_has() {
  command -v "$1" >/dev/null 2>&1
}

srv_tune_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

srv_tune_warn() {
  printf 'warn: %s\n' "$*" >&2
}
