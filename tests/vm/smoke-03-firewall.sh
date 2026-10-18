#!/usr/bin/env bash
# Scenario 03: firewall apply + persistence. Reboot part is human-only.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

snapshot_checkpoint "03-firewall" || exit 2
rv_run "cd /tmp/temper && sudo ./optimizer.sh apply --profile generic --only firewall --with-firewall --yes" || exit 1
rv_run "(sudo ufw status numbered || sudo nft list ruleset) | head -n 30" || exit 1
human_only "firewall persistence across reboot" \
  "sudo reboot the VM" \
  "reconnect and run: sudo ufw status || sudo nft list ruleset" \
  "confirm the temper rules survived; record the output in $SMOKE_LOG by hand"
