#!/usr/bin/env bash
# Scenario 02: port change + unconfirmed-guard revert + close-22. DESTRUCTIVE.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

snapshot_checkpoint "02-port-guard" || exit 2
rv_run "cd /tmp/srv-tune && sudo SRV_TUNE_SSH_PORT=2222 ./optimizer.sh apply --profile generic --only ssh --with-ssh --yes" || exit 1
rv_run "ss -tlnp | grep -E ':(22|2222) '" || exit 1
smoke_log "guard id printed above; letting it expire WITHOUT confirming..."
sleep 330
rv_run "ss -tlnp | grep ':2222 ' && echo STILL-THERE || echo REVERTED" || exit 1
rv_run "grep -c '^Port 2222' /etc/ssh/sshd_config.d/00-srv-tune.conf || echo DROPIN-GONE" || exit 1
smoke_log "now redo + confirm from THIS (new) session, then close 22 only if 22222 listens"
