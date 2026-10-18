#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Scanner orchestrator: read-only. Human report + JSON + score + profile.
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/lib/log.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/i18n.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/preflight.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/collectors/os.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/collectors/hw.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/collectors/net.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/collectors/ssh.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/collectors/fw.sh"
# shellcheck disable=SC1091
source "$ROOT/scanner/report.sh"

RECOMMEND_ONLY=0
for a in "$@"; do
  [[ "$a" == "--recommend-only" ]] && RECOMMEND_ONLY=1
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Collect (each is read-only, best-effort, never fails the scan).
collect_os >"$TMP/all.env" 2>/dev/null || true
collect_hw >>"$TMP/all.env" 2>/dev/null || true
collect_net >>"$TMP/all.env" 2>/dev/null || true
collect_ssh >>"$TMP/all.env" 2>/dev/null || true
collect_fw >>"$TMP/all.env" 2>/dev/null || true

# OS tier for scoring.
TIER="$(preflight_os_tier 2>/dev/null || printf 'unsupported')"
printf 'OS_TIER=%s\n' "$TIER" >>"$TMP/all.env"

# shellcheck disable=SC1091
source "$TMP/all.env"

SCORE="$(compute_score)"
PROFILE="$(recommend_profile)"
RECS="$(list_recommendations)"

json_escape_local() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

JSON="{"
first=1
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && continue
  if [[ $first -eq 0 ]]; then JSON="$JSON,"; fi
  first=0
  JSON="$JSON\"$(json_escape_local "$k")\":\"$(json_escape_local "$v")\""
done <"$TMP/all.env"
JSON="$JSON,\"SCORE\":\"$SCORE\",\"PROFILE\":\"$(json_escape_local "$PROFILE")\"}"

OUT="${TEMPER_JSON_OUT:-${JSON_OUT:-}}"
if [[ -n "$OUT" ]]; then
  printf '%s\n' "$JSON" >"$OUT"
fi

if [[ -n "${TEMPER_SCAN_DIFF:-}" ]]; then
  # Compare against a stored scan instead of printing the full report.
  # shellcheck disable=SC1091
  source "$ROOT/scanner/diff.sh"
  rc=0
  scan_diff_run "$TEMPER_SCAN_DIFF" "$TMP/all.env" "$SCORE" "$PROFILE" || rc=$?
  exit "$rc"
fi

if [[ "$RECOMMEND_ONLY" == "1" ]]; then
  printf 'profile: %s\nscore: %s/100\n' "$PROFILE" "$SCORE"
  printf '%s\n' "$RECS"
  exit 0
fi

# Human report (stdout; UI language via i18n).
cat <<EOF
$(t scan_done): temper $SCORE/100
OS: ${OS_ID:-?} ${OS_VERSION:-?} ($TIER) kernel ${KERNEL:-?} init ${INIT:-?} virt ${VIRT:-?}
CPU: ${CPU_CORES:-?} cores AES-NI=${AES_NI:-?}  RAM: ${RAM_KB:-?}kB swap ${SWAP_KB:-?}kB
Disk: ${DISK_TYPE:-?} free ${DISK_FREE_KB:-?}kB  IF: ${IFACE:-?} MTU=${MTU:-?} IPv6=${IPV6:-?}
CC=${CC:-?} qdisc=${QDISC:-?} DNS=${DNS:-?}
Mirror: ${MIRROR:-?}  PublicIP: ${PUBLIC_IP:-?} cloud-init=${CLOUD_INIT:-?}
SSH: port=${SSH_PORT:-?} root=${SSH_ROOT:-?} pass=${SSH_PASS:-?} listen=${SSH_LISTEN:-?} ok=${SSH_OK:-?}
FW: ${FIREWALL:-?} fail2ban=${FAIL2BAN:-?} tuned=${TUNED:-?} ports=${OPEN_PORTS:-?}
Recommended profile: $PROFILE ($(t accept_recommended))
Recommendations:
$RECS
JSON: $JSON
EOF
