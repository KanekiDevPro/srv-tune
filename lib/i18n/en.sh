#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# English UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
  app_title) printf 'srv-tune server optimizer' ;;
  accept_recommended) printf 'Press Enter to accept the recommended profile' ;;
  scan_done) printf 'Scan complete' ;;
  choose_profile) printf 'Choose a profile (recommended shown first)' ;;
  risk_ssh) printf 'RISK ssh: a bad sshd config or firewall rule LOCKS YOU OUT. Keep one proven session open. After apply, confirm from a NEW session with: srv-tune confirm <id>. Silence auto-reverts.' ;;
  risk_firewall) printf 'RISK firewall: default-deny can cut this session and every service port. The ssh port is allowed first and a timed auto-revert is armed. Confirm from a NEW session.' ;;
  type_ssh) printf 'Type SSH-YES to apply ssh changes (anything else aborts)' ;;
  type_firewall) printf 'Type FIREWALL-YES to apply firewall changes (anything else aborts)' ;;
  need_with_ssh) printf 'ssh needs --with-ssh plus typed confirmation (see risks above)' ;;
  need_with_firewall) printf 'firewall/fail2ban needs --with-firewall plus typed confirmation (see risks above)' ;;
  aborted) printf 'aborted by operator, nothing was changed' ;;
  *) return 1 ;;
  esac
}
