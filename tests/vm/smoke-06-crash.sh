#!/usr/bin/env bash
# Scenario 06: kill -9 between write and validate (guarded crash + timer).
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

snapshot_checkpoint "06-crash" || exit 2
# The applier is EXPECTED to die (137) at the crash hook; run it tolerantly
# (set -e would abort on the 137) and assert on the recorded output instead.
rv_run "cd /tmp/temper && sudo TEMPER_CRASH_AFTER_WRITE=1 TEMPER_GUARD_TIMEOUT=15 ./optimizer.sh apply --profile generic --only ssh --with-ssh --yes; echo APPLIER-RC=\$?" || true
grep -q "APPLIER-RC=137" "$SMOKE_LOG" || {
  smoke_log "expected the applier to die with 137 at the crash hook"
  exit 1
}
smoke_log "applier died mid-run by design; waiting for the real timer..."
sleep 30
rv_run "grep -c temper /etc/ssh/sshd_config.d/00-temper.conf || echo DROPIN-REVERTED" || exit 1
