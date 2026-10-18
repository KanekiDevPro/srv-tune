#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# English UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
  app_title) printf 'temper server optimizer' ;;
  accept_recommended) printf 'Press Enter to accept the recommended profile' ;;
  scan_done) printf 'Scan complete' ;;
  choose_profile) printf 'Choose a profile (recommended shown first)' ;;
  risk_ssh) printf 'RISK ssh: a bad sshd config or firewall rule LOCKS YOU OUT. Keep one proven session open. After apply, confirm from a NEW session with: temper confirm <id>. Silence auto-reverts.' ;;
  risk_firewall) printf 'RISK firewall: default-deny can cut this session and every service port. The ssh port is allowed first and a timed auto-revert is armed. Confirm from a NEW session.' ;;
  type_ssh) printf 'Type SSH-YES to apply ssh changes (anything else aborts)' ;;
  type_firewall) printf 'Type FIREWALL-YES to apply firewall changes (anything else aborts)' ;;
  need_with_ssh) printf 'ssh needs --with-ssh plus typed confirmation (see risks above)' ;;
  need_with_firewall) printf 'firewall/fail2ban needs --with-firewall plus typed confirmation (see risks above)' ;;
  need_with_registry) printf 'registry mirrors need --with-registry plus typed confirmation (see risks above)' ;;
  risk_registry) printf 'RISK registry mirrors: NOT signed like apt; a mirror operator can serve altered packages. Review owner/docs in data/. HTTPS only. Never in default profiles.' ;;
  type_registry) printf 'Type REGISTRY-YES to apply registry mirrors (anything else aborts)' ;;
  risk_dns_extra) printf 'RISK extra resolvers: a third-party resolver sees EVERY query and may return altered answers (censorship, hijack). Use only resolvers you trust. Extras are never auto-selected.' ;;
  type_dns_extra) printf 'Type DNS-EXTRA-YES to use extra resolvers (anything else aborts)' ;;
  aborted) printf 'aborted by operator, nothing was changed' ;;
  tunnel_title) printf 'Tunnel' ;;
  tunnel_keys) printf 'Keys' ;;
  tunnel_access) printf 'Access policy' ;;
  tunnel_sessions) printf 'Sessions' ;;
  tunnel_refresh) printf 'Refresh' ;;
  tunnel_quit) printf 'Quit' ;;
  tunnel_back) printf 'Back' ;;
  tunnel_add) printf 'Add' ;;
  tunnel_remove) printf 'Remove' ;;
  tunnel_list) printf 'List' ;;
  tunnel_edit) printf 'Edit' ;;
  tunnel_permits) printf 'PermitOpen (none or host:port[,host:port])' ;;
  tunnel_gateway) printf 'GatewayPorts (yes/no)' ;;
  tunnel_risk) printf 'RISK: this rewrites the TUNNEL sshd drop-in; a bad value can cut your own access. After the reload, prove a NEW session before the guard expires.' ;;
  tunnel_confirm) printf 'Type SSH-YES to rewrite the tunnel access policy:' ;;
  *) return 1 ;;
  esac
}
