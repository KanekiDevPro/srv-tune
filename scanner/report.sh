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
  # if-form (not && chains): a false filter must exit 0, never abort set -e callers.
  if [[ "${SSH_PASS:-}" == "yes" ]]; then score=$((score - 15)); fi
  if [[ "${SSH_ROOT:-}" == "yes" ]]; then score=$((score - 10)); fi
  if [[ "${FIREWALL:-none}" == "none" ]]; then score=$((score - 10)); fi
  if [[ "${TUNED:-no}" == "no" ]]; then score=$((score - 5)); fi
  if [[ "${SWAP_KB:-0}" == "0" ]]; then score=$((score - 5)); fi
  if [[ "${CC:-}" != "bbr" ]]; then score=$((score - 5)); fi
  if [[ "$score" -lt 0 ]]; then score=0; fi
  if [[ "$score" -gt 100 ]]; then score=100; fi
  printf '%s\n' "$score"
}

recommend_profile() {
  local ram="${RAM_KB:-0}"
  # low-ram <=1GB
  if [[ "$ram" != "0" ]] && [[ "$ram" -le 1048576 ]]; then
    printf 'low-ram\n'
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    printf 'docker\n'
    return 0
  fi
  if command -v mysqld >/dev/null 2>&1 || command -v postgres >/dev/null 2>&1 || command -v redis-server >/dev/null 2>&1; then
    printf 'database\n'
    return 0
  fi
  if command -v nginx >/dev/null 2>&1; then
    printf 'web\n'
    return 0
  fi
  printf 'generic\n'
}

list_recommendations() {
  # if-form (not && chains): a false filter must exit 0, never abort set -e callers.
  if [[ "${OS_TIER:-}" == "eol" ]]; then printf 'upgrade-os: OS is EOL, upgrade before tuning (why: unsupported kernel/userspace)\n'; fi
  if [[ "${SSH_PASS:-}" == "yes" ]]; then printf 'ssh-admin: disable PasswordAuthentication after key verified (why: brute-force risk)\n'; fi
  if [[ "${SSH_ROOT:-}" == "yes" ]]; then printf 'ssh-admin: set PermitRootLogin no (why: least privilege)\n'; fi
  if [[ "${FIREWALL:-none}" == "none" ]]; then printf 'security: enable ufw/nftables (why: reduce attack surface)\n'; fi
  if [[ "${DOCKER:-no}" == "yes" && "${FIREWALL:-none}" != "none" ]]; then printf 'security: docker publishes ports outside ufw (why: bypass; use DOCKER-USER chain or nftables)\n'; fi
  if [[ "${CC:-}" != "bbr" ]]; then printf 'network: enable BBR+fq if kernel supports it (why: higher throughput)\n'; fi
  if [[ "${TUNED:-no}" == "no" ]]; then printf 'network: apply sysctl drop-in 00-srv-tune.conf (why: buffers from RAM/BW)\n'; fi
  if [[ "${AES_NI:-}" == "no" ]]; then printf 'ssh: prefer chacha20-poly1305 (why: no AES-NI)\n'; fi
  if [[ "${SWAP_KB:-0}" == "0" ]]; then printf 'kernel: consider zram on low RAM (why: avoid OOM)\n'; fi
}
