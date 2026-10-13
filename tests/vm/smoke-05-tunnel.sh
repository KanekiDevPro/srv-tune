#!/usr/bin/env bash
# Scenario 05: TUNNEL restrictions (dry-run + config content only).
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

rv_run "cd /tmp/srv-tune && sudo ./optimizer.sh apply --profile vpn-tunnel --dry-run" || exit 1
human_only "live TUNNEL apply" \
  "review the dry-run above line by line" \
  "only then run the real apply with --with-ssh and confirm from a NEW session" \
  "verify: Match User tunnel has PermitTTY no + ForceCommand nologin + explicit PermitOpen"
