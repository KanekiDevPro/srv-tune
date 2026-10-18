#!/usr/bin/env bash
# Scenario 01: ssh.socket vs ssh.service detection (read-only).
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

rv_run "systemctl list-sockets | grep -i ssh || true" || exit 1
rv_run "systemctl is-active ssh.socket ssh.service || true" || exit 1
rv_run "ss -tlnp | grep ':22 ' || true" || exit 1
rv_run "cd /tmp/temper && sudo ./optimizer.sh apply --profile generic --only ssh --dry-run" || exit 1
smoke_log "socket/service behavior recorded; no changes made (dry-run only)"
