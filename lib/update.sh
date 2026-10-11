#!/usr/bin/env bash
# Self-update: explicit only, checksum-verified, no telemetry.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_UPDATE_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_UPDATE_SOURCED=1

self_update() {
  local repo="${SRV_TUNE_UPDATE_REPO:-}"
  if [[ -z "$repo" ]]; then
    printf 'error: update repo not configured\n' >&2
    return 1
  fi
  printf 'update from %s is not yet implemented in v0.1 (MVP)\n' "$repo" >&2
  return 2
}
