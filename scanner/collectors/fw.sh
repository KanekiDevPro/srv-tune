#!/usr/bin/env bash
# Firewall + ports collector (read-only).
# shellcheck shell=bash

collect_fw() {
  local fw="none" ports="unknown" f2b="no" tuned="no"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'active'; then
    fw="ufw"
  elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q 'chain'; then
    fw="nftables"
  elif command -v iptables >/dev/null 2>&1 && iptables -L -n 2>/dev/null | grep -qv 'Chain'; then
    fw="iptables"
  fi
  if command -v ss >/dev/null 2>&1; then
    ports="$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | tr '\n' ',' | sed -E 's/,$//' || true)"
    if [[ -z "$ports" ]]; then ports="none"; fi
  fi
  if systemctl is-active fail2ban >/dev/null 2>&1; then
    f2b="yes"
  fi
  if ls /etc/sysctl.d/*.conf >/dev/null 2>&1; then
    tuned="yes"
  fi
  printf 'FIREWALL=%s\nOPEN_PORTS=%s\nFAIL2BAN=%s\nTUNED=%s\n' \
    "$fw" "$ports" "$f2b" "$tuned"
}
