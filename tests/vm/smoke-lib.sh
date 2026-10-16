#!/usr/bin/env bash
# Shared helpers for the disposable-VM smoke harness. Nothing here runs in CI.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash

SMOKE_ALIAS="${SMOKE_ALIAS:-}"
SMOKE_LOGDIR="${SMOKE_LOGDIR:-}"
SMOKE_LOG="${SMOKE_LOG:-/dev/null}"

smoke_log() {
  printf '%s\n' "$*" | tee -a "$SMOKE_LOG"
}

# rv_run <cmd...> - run a remote command, log it raw, STOP on SSH loss.
rv_run() {
  local rc
  printf '+ ssh %s %s\n' "$SMOKE_ALIAS" "$*" >>"$SMOKE_LOG"
  # shellcheck disable=SC2029
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$SMOKE_ALIAS" "$@" >>"$SMOKE_LOG" 2>&1
  rc=$?
  if [[ "$rc" == "255" ]]; then
    smoke_log "SSH LOST (exit 255). STOPPING. Use the VM console to recover;"
    smoke_log "then restore the snapshot before re-running anything."
    return 3
  fi
  return "$rc"
}

# snapshot_checkpoint <name> - restore point between destructive scenarios.
snapshot_checkpoint() {
  local name="$1"
  if [[ -z "${SNAPSHOT_RESTORE_HOOK:-}" ]]; then
    smoke_log "REFUSING destructive scenario '$name': set SNAPSHOT_RESTORE_HOOK first."
    return 2
  fi
  smoke_log "--- snapshot checkpoint before $name ---"
  bash -c "$SNAPSHOT_RESTORE_HOOK" >>"$SMOKE_LOG" 2>&1 || {
    smoke_log "snapshot hook failed; STOPPING."
    return 2
  }
  return 0
}

human_only() {
  # human_only <title> <step>... - print manual steps, never claim verified.
  local title="$1"
  shift
  smoke_log "HUMAN-ONLY: $title (not verified by this harness)"
  local s
  for s in "$@"; do
    smoke_log "  HUMAN STEP: $s"
  done
  return 0
}
