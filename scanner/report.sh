#!/usr/bin/env bash
# Scoring + profile recommendation + prioritized list (pure function over env).
# Inputs: KEY=VALUE vars in environment. Outputs: SCORE, PROFILE, RECS.
# shellcheck shell=bash

compute_score() {
  local score=100
  local tier="${OS_TIER:-unsupported}"
  case "$tier" in
    eol) score=$((score - 30)) ;;
    unsupported) score=$((score - 15)) ;;
    tier2) score=$((score - 5)) ;;
    best-effort) score=$((score - 10)) ;;
  esac
  [[ "${SSH_PASS:-}" == "yes" ]] && score=$((score - 15))
  [[ "${SSH_ROOT:-}" == "yes" ]] && score=$((score - 10))
  [[ "${FIREWALL:-none}" == "none" ]] && score=$((score - 10))
  [[ "${TUNED:-no}" == "no" ]] && score=$((score - 5))
  [[ "${SWAP_KB:-0}" == "0" ]] && score=$((score - 5))
  [[ "${CC:-}" != "bbr" ]] && score=$((score - 5))
  [[ "$score" -lt 0 ]] && score=0
  [[ "$score" -gt 100 ]] && score=100
  printf '%s\n' "$score"
}

recommend_profile() {
  local ram="${RAM_KB:-0}"
  # low-ram <=1GB
  if [[ "$ram" != "0" ]] && [[ "$ram" -le 1048576 ]]; then
    printf 'low-ram\n'; return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    printf 'docker\n'; return 0
  fi
  if command -v mysqld >/dev/null 2>&1 || command -v postgres >/dev/null 2>&1 || command -v redis-server >/dev/null 2>&1; then
    printf 'database\n'; return 0
  fi
  if command -v nginx >/dev/null 2>&1; then
    printf 'web\n'; return 0
  fi
  printf 'generic\n'
}

list_recommendations() {
  [[ "${OS_TIER:-}" == "eol" ]] && printf 'upgrade-os: OS is EOL, upgrade before tuning (why: unsupported kernel/userspace)\n'
  [[ "${SSH_PASS:-}" == "yes" ]] && printf 'ssh-admin: disable PasswordAuthentication after key verified (why: brute-force risk)\n'
  [[ "${SSH_ROOT:-}" == "yes" ]] && printf 'ssh-admin: set PermitRootLogin no (why: least privilege)\n'
  [[ "${FIREWALL:-none}" == "none" ]] && printf 'security: enable ufw/nftables (why: reduce attack surface)\n'
  [[ "${CC:-}" != "bbr" ]] && printf 'network: enable BBR+fq if kernel supports it (why: higher throughput)\n'
  [[ "${TUNED:-no}" == "no" ]] && printf 'network: apply sysctl drop-in 00-srv-tune.conf (why: buffers from RAM/BW)\n'
  [[ "${AES_NI:-}" == "no" ]] && printf 'ssh: prefer chacha20-poly1305 (why: no AES-NI)\n'
  [[ "${SWAP_KB:-0}" == "0" ]] && printf 'kernel: consider zram on low RAM (why: avoid OOM)\n'
  return 0
}
