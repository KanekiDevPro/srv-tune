#!/usr/bin/env bash
# Disposable-VM smoke harness. Records raw commands+outputs per scenario.
# Usage: tests/vm/run-all.sh <ssh-alias> <os>
#   SNAPSHOT_RESTORE_HOOK="multipass restore ..." tests/vm/run-all.sh vm1 ubuntu-24.04
# Refuses localhost / the current host. Stops on SSH loss. Reboot persistence
# and console recovery are human-only (printed, never claimed as verified).
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail

ALIAS="${1:-}"
OS="${2:-}"
if [[ -z "$ALIAS" || -z "$OS" ]]; then
  printf 'usage: run-all.sh <ssh-alias> <os>\n' >&2
  exit 2
fi

# --- localhost / current-host refusal (checked twice, two mechanisms) ---
case "$ALIAS" in
localhost | 127.* | ::1)
  printf 'error: refusing to run against %s (localhost)\n' "$ALIAS" >&2
  exit 2
  ;;
esac
remote_host="$(ssh -G "$ALIAS" 2>/dev/null | awk '/^hostname /{print $2}' || true)"
local_names="$(
  hostname 2>/dev/null
  hostname -f 2>/dev/null
  hostname -I 2>/dev/null || true
)"
if [[ -n "$remote_host" ]]; then
  # shellcheck disable=SC2086
  for n in $local_names localhost 127.0.0.1 ::1; do
    if [[ "$remote_host" == "$n" ]]; then
      printf 'error: alias %s resolves to this machine (%s); refusing\n' "$ALIAS" "$n" >&2
      exit 2
    fi
  done
fi
remote_uname="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" hostname 2>/dev/null || true)"
if [[ -n "$remote_uname" && "$remote_uname" == "$(hostname 2>/dev/null)" ]]; then
  printf 'error: alias %s IS this host (hostname %s); refusing\n' "$ALIAS" "$remote_uname" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DATE="$(date '+%Y-%m-%d')"
LOGDIR="$ROOT/docs/vm-logs/$OS-$DATE"
mkdir -p "$LOGDIR"
export SMOKE_ALIAS="$ALIAS" SMOKE_LOGDIR="$LOGDIR"
# shellcheck disable=SC1091
source "$ROOT/tests/vm/smoke-lib.sh"

printf 'smoke run: alias=%s os=%s logs=%s\n' "$ALIAS" "$OS" "$LOGDIR"
for s in 00-prepare 01-socket-service 02-port-guard 03-firewall 04-fail2ban 05-tunnel 06-crash; do
  export SMOKE_LOG="$LOGDIR/$s.log"
  : >"$SMOKE_LOG"
  smoke_log "=== scenario $s (alias=$ALIAS os=$OS) ==="
  if ! bash "$ROOT/tests/vm/smoke-$s.sh"; then
    smoke_log "SCENARIO $s FAILED OR STOPPED; see above. Fix via console, restore snapshot, re-run."
    exit 1
  fi
  smoke_log "=== scenario $s done ==="
done
printf 'smoke run complete. Logs in %s\n' "$LOGDIR"
