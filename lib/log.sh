#!/usr/bin/env bash
# Logging helpers. English only (logs stay English per policy).
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_LOG_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_LOG_SOURCED=1

: "${SRV_TUNE_LOG_LEVEL:=INFO}"

_log_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '[%s] INFO: %s\n' "$(_log_ts)" "$*"
}

log_warn() {
  printf '[%s] WARN: %s\n' "$(_log_ts)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(_log_ts)" "$*" >&2
}

log_debug() {
  if [[ "${SRV_TUNE_LOG_LEVEL}" == "DEBUG" ]]; then
    printf '[%s] DEBUG: %s\n' "$(_log_ts)" "$*" >&2
  fi
}
