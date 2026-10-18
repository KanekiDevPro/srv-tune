#!/usr/bin/env bash
# Scenario 00: reachability + code drop + read-only baseline. Not destructive.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
smoke_log "copying tree to the VM (scp, no installs)"
scp -r -o BatchMode=yes "$ROOT/optimizer.sh" "$ROOT/lib" "$ROOT/modules" "$ROOT/scanner" "$ROOT/profiles" "$ROOT/bench" "$ROOT/data" "$ROOT/templates" "$ROOT/VERSION" "$SMOKE_ALIAS:/tmp/temper/" >>"$SMOKE_LOG" 2>&1 || {
  smoke_log "scp failed; check the alias and keys"
  exit 1
}
rv_run "cd /tmp/temper && ./optimizer.sh status" || exit 1
rv_run "cd /tmp/temper && ./optimizer.sh scan" || exit 1
rv_run "cd /tmp/temper && ./optimizer.sh audit" || exit 1
smoke_log "baseline captured"
