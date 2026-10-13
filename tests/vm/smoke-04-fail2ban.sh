#!/usr/bin/env bash
# Scenario 04: fail2ban ignoreip + external ban. Needs a second source IP.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/smoke-lib.sh"

snapshot_checkpoint "04-fail2ban" || exit 2
rv_run "cd /tmp/srv-tune && sudo ./optimizer.sh apply --profile generic --only fail2ban --with-firewall --yes" || exit 1
rv_run "cat /etc/fail2ban/jail.d/00-srv-tune.local" || exit 1
rv_run "sudo fail2ban-client status sshd || true" || exit 1
human_only "external ban proof" \
  "from ANOTHER host (not this session IP), fail 6+ ssh logins with a bad password" \
  "on the VM run: sudo fail2ban-client status sshd (attack IP must be banned)" \
  "confirm your session IP never appears banned; record outputs by hand"
