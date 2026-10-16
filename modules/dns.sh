#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# dns: benchmark candidate resolvers live, apply fastest via resolved,
# resolv.conf or netplan; cloud-init respected; rollback on broken resolution.
# DoT stays off unless port 853 is reachable (then it is only OFFERED).
# Benchmarks: 2s timeout, max 4 parallel, contacted hosts always printed.
# Contract: dns_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

dns_tool() {
  # SRV_TUNE_DNS_TOOL overrides auto-detect (tests force the drill path).
  if [[ -n "${SRV_TUNE_DNS_TOOL:-}" ]]; then
    printf '%s\n' "$SRV_TUNE_DNS_TOOL"
    return 0
  fi
  if command -v dig >/dev/null 2>&1; then
    printf 'dig\n'
  elif command -v drill >/dev/null 2>&1; then
    printf 'drill\n'
  else
    printf 'none\n'
  fi
}

dns_probe_host() {
  printf '%s\n' "${SRV_TUNE_DNS_PROBE:-example.com}"
}

dns_candidates() {
  local root="${SRV_TUNE_ROOT:-.}" f line ip tier
  f="$root/data/dns-resolvers.list"
  [[ -f "$f" ]] || return 0
  # Automatic pool = tier default only. Optional resolvers join only via
  # --dns-extra (see dns_extra_candidates): they are never auto-selected.
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    data_entry_verified "$line" || continue
    tier="$(data_entry_tier "$line")"
    [[ "$tier" == "default" ]] || continue
    ip="$(printf '%s' "$line" | awk '{print $1}')"
    [[ -n "$ip" ]] && printf '%s\n' "$ip"
  done <"$f"
  dns_extra_candidates "$f"
}

# dns_extra_candidates <listfile> - IPs for --dns-extra IDs (comma-separated).
# Each ID must exist with tier optional (verified or test override applies).
# Unknown IDs fail loudly with the valid list.
dns_extra_candidates() {
  local f="$1" extra="${SRV_TUNE_DNS_EXTRA:-}" name
  [[ -z "$extra" ]] && return 0
  local IFS=','
  # shellcheck disable=SC2086
  for name in $extra; do
    name="$(printf '%s' "$name" | tr -d ' ')"
    [[ -z "$name" ]] && continue
    dns_extra_one "$f" "$name" || return 1
  done
}

# dns_extra_one <listfile> <id> - print the IP for one optional entry.
dns_extra_one() {
  local f="$1" want="$2" line id ip tier
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    data_entry_verified "$line" || continue
    id="$(printf '%s' "$line" | awk '{print $2}')"
    [[ "$id" == "$want" ]] || continue
    tier="$(data_entry_tier "$line")"
    if [[ "$tier" != "optional" ]]; then
      printf 'error: --dns-extra %s is tier %s, not optional (extra flag is only for optional resolvers)\n' "$want" "$tier" >&2
      return 1
    fi
    ip="$(printf '%s' "$line" | awk '{print $1}')"
    [[ -n "$ip" ]] && printf '%s\n' "$ip"
    return 0
  done <"$f"
  printf 'error: unknown --dns-extra ID: %s (valid optional IDs: %s)\n' "$want" "$(dns_optional_ids "$f")" >&2
  return 1
}

# dns_optional_ids <listfile> - comma list of usable optional IDs (for errors).
dns_optional_ids() {
  local f="$1" line id out=""
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    data_entry_verified "$line" || continue
    [[ "$(data_entry_tier "$line")" == "optional" ]] || continue
    id="$(printf '%s' "$line" | awk '{print $2}')"
    [[ -n "$id" ]] && out="${out}${out:+,}$id"
  done <"$f"
  printf '%s\n' "$out"
}

# dns_probe_one <ip> <probe> <out> - single probe via dig (or drill
# fallback); appends "ip ms ok|fail". drill carries its own retry budget.
dns_probe_one() {
  local ip="$1" probe="$2" out="$3" txt ms tool
  tool="$(dns_tool)"
  if [[ "$tool" == "drill" ]]; then
    txt="$(drill "$probe" "@$ip" 2>/dev/null || true)"
  else
    txt="$(dig +time=2 +tries=1 "@$ip" "$probe" 2>/dev/null || true)"
  fi
  if printf '%s' "$txt" | grep -q 'IN A'; then
    ms="$(printf '%s' "$txt" | grep 'Query time' | grep -o '[0-9][0-9]* msec' | awk '{print $1}' | head -n 1)"
    [[ -z "$ms" ]] && ms=9999
    printf '%s %s ok\n' "$ip" "$ms" >>"$out"
  else
    printf '%s 0 fail\n' "$ip" >>"$out"
  fi
}

# dns_benchmark - two rounds, max 4 parallel; prints "ip ms fails/2" sorted.
dns_benchmark() {
  local probe tmp ip _round
  probe="$(dns_probe_host)"
  tmp="$(mktemp)"
  printf 'contacting resolvers:' >&2
  while IFS= read -r ip; do
    printf ' %s' "$ip" >&2
  done < <(dns_candidates)
  printf '\n' >&2
  local _round
  for _round in 1 2; do
    while IFS= read -r ip; do
      while [[ "$(jobs -r | wc -l)" -ge 4 ]]; do
        wait -n 2>/dev/null || wait
      done
      dns_probe_one "$ip" "$probe" "$tmp" &
    done < <(dns_candidates)
    wait
  done
  local ms fails
  while IFS= read -r ip; do
    ms="$(awk -v ip="$ip" '$1==ip && $3=="ok" {s+=$2; n++} END {if (n>0) print int(s/n); else print ""}' "$tmp")"
    fails="$(awk -v ip="$ip" '$1==ip && $3=="fail" {n++} END {print n+0}' "$tmp")"
    if [[ -z "$ms" ]]; then
      printf '%s down %s/2\n' "$ip" "$fails"
    else
      printf '%s %s %s/2\n' "$ip" "$ms" "$fails"
    fi
  done < <(dns_candidates) | sort -t' ' -k2,2n
  rm -f "$tmp"
}

# dns_winners - top two working resolver IPs, one per line.
dns_winners() {
  dns_benchmark 2>/dev/null | awk '$2 != "down" {print $1}' | head -n 2
}

dns_backend() {
  if [[ -d "$(sys_p /run/systemd/resolve)" ]] && command -v systemctl >/dev/null 2>&1 && systemctl is-active systemd-resolved >/dev/null 2>&1; then
    printf 'resolved\n'
  elif command -v netplan >/dev/null 2>&1 && ls "$(sys_p /etc/netplan/)"*.yaml >/dev/null 2>&1; then
    printf 'netplan\n'
  else
    printf 'resolv.conf\n'
  fi
}

dns_cloud_managed() {
  grep -rq 'manage-resolv-conf:[[:space:]]*true' "$(sys_p /etc/cloud/)" 2>/dev/null
}

dns_detect() {
  printf 'TOOL=%s\nBACKEND=%s\n' "$(dns_tool)" "$(dns_backend)"
  if dns_cloud_managed; then
    printf 'CLOUD_DNS=yes\n'
  else
    printf 'CLOUD_DNS=no\n'
  fi
  printf 'CURRENT=%s\n' "$(grep -E '^nameserver' "$(sys_p /etc/resolv.conf)" 2>/dev/null | awk '{print $2}' | tr '\n' ',' || true)"
}

dns_recommend() {
  if [[ "$(dns_tool)" == "none" ]]; then
    printf 'skip: neither dig nor drill installed (why: cannot benchmark; install dnsutils/ldnsutils or set resolvers manually)\n'
    return 0
  fi
  local bench w1 w2
  printf 'benchmark (why: latency + failure rate from THIS server):\n'
  bench="$(dns_benchmark)"
  printf '%s\n' "$bench"
  printf 'pick: fastest with 0/2 failures as primary, second as secondary (why: redundancy)\n'
  w1="$(printf '%s' "$bench" | awk '$2 != "down" {print $1}' | sed -n '1p')"
  w2="$(printf '%s' "$bench" | awk '$2 != "down" {print $1}' | sed -n '2p')"
  dns_dot_offer "$w1" "$w2"
}

# dns_dot_probe <ip> - 0 when TCP 853 answers, 1 when closed, 2 when the
# host cannot test (no timeout tool). SRV_TUNE_DOT_PROBE=open|closed is a
# test seam; production always probes the wire.
dns_dot_probe() {
  local ip="$1"
  case "${SRV_TUNE_DOT_PROBE:-}" in
  open) return 0 ;;
  closed) return 1 ;;
  esac
  command -v timeout >/dev/null 2>&1 || return 2
  timeout 3 bash -c 'echo > /dev/tcp/'"$ip"'/853' 2>/dev/null
}

# dns_dot_offer [ip...] - per-winner DoT reachability. An offer only, DoT
# is never enabled here (dns_apply needs explicit --with-dot).
dns_dot_offer() {
  local ip rc
  for ip in "$@"; do
    [[ -z "$ip" ]] && continue
    dns_dot_probe "$ip"
    rc=$?
    if [[ "$rc" == "0" ]]; then
      printf 'dot: %s port 853 reachable (why: DoT stays off unless you pass --with-dot)\n' "$ip"
    elif [[ "$rc" == "1" ]]; then
      printf 'dot: %s port 853 closed (why: DoT not offered for this resolver)\n' "$ip"
    else
      printf 'dot: %s reachability unchecked (why: no timeout tool here; DoT not offered)\n' "$ip"
    fi
  done
}

dns_apply() {
  local backup_dir="$1" backend winners w1 w2 tmp dot="no"
  if [[ "$(dns_tool)" == "none" ]]; then
    printf 'skip: neither dig nor drill, nothing to benchmark\n'
    return 2
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  # shellcheck disable=SC1091
  declare -F t >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/../lib/i18n.sh"
  # shellcheck disable=SC1091
  declare -F ui_type_confirm >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/../lib/ui.sh"
  if [[ -n "${SRV_TUNE_DNS_EXTRA:-}" ]]; then
    printf '%s\n' "$(t risk_dns_extra)"
    if ! ui_type_confirm "$(t type_dns_extra)" "DNS-EXTRA-YES"; then
      printf '%s\n' "$(t aborted)"
      return 1
    fi
  fi
  winners="$(dns_winners)"
  w1="$(printf '%s' "$winners" | sed -n '1p')"
  w2="$(printf '%s' "$winners" | sed -n '2p')"
  if [[ -z "$w1" ]]; then
    printf 'error: every candidate resolver failed; refusing to apply\n' >&2
    return 1
  fi
  if [[ -z "$w2" ]]; then w2="$w1"; fi
  backend="$(dns_backend)"
  # DoT is off by default and needs systemd-resolved: the stubs it writes
  # elsewhere cannot speak TLS. Winners must prove port 853 first.
  if [[ "${SRV_TUNE_WITH_DOT:-0}" == "1" ]]; then
    if [[ "$backend" != "resolved" ]]; then
      printf 'error: --with-dot needs the systemd-resolved backend (this host uses %s, which cannot do DoT)\n' "$backend" >&2
      return 1
    fi
    local rip
    for rip in "$w1" "$w2"; do
      if ! dns_dot_probe "$rip"; then
        printf 'error: refusing --with-dot: winner %s lacks reachable port 853\n' "$rip" >&2
        return 1
      fi
    done
    dot="yes"
  fi
  if [[ "$backend" == "resolved" ]]; then
    tmp="$(mktemp)"
    {
      printf '# srv-tune DNS (why: benchmarked fastest)\n[Resolve]\nDNS=%s %s\nFallbackDNS=1.1.1.1 8.8.8.8\nDNSOverTLS=%s\n' "$w1" "$w2" "$dot"
    } >"$tmp"
    apply_file "$backup_dir" "$(sys_p /etc/systemd/resolved.conf.d/00-srv-tune.conf)" "$tmp" "fastest resolvers $w1 $w2" || return 1
    if [[ "${SRV_TUNE_DRY_RUN:-0}" != "1" && "${SRV_TUNE_TEST:-0}" != "1" ]]; then
      systemctl restart systemd-resolved 2>/dev/null || printf 'warn: resolved restart failed\n' >&2
    fi
  elif [[ "$backend" == "netplan" ]]; then
    tmp="$(mktemp)"
    {
      printf '# srv-tune DNS\nnetwork:\n  version: 2\n  ethernets:\n    srv-tune:\n      match:\n        name: "e*"\n      nameservers:\n        addresses: [%s, %s]\n' "$w1" "$w2"
    } >"$tmp"
    apply_file "$backup_dir" "$(sys_p /etc/netplan/00-srv-tune.yaml)" "$tmp" "fastest resolvers $w1 $w2" || return 1
    if [[ "${SRV_TUNE_DRY_RUN:-0}" != "1" && "${SRV_TUNE_TEST:-0}" != "1" ]] && command -v netplan >/dev/null 2>&1; then
      netplan generate 2>/dev/null || {
        printf 'error: netplan generate rejected the config\n' >&2
        return 1
      }
    fi
  else
    if dns_cloud_managed; then
      printf 'error: resolv.conf is cloud-init managed; refusing (why: changes would be overwritten)\n' >&2
      return 1
    fi
    tmp="$(mktemp)"
    {
      printf '# srv-tune DNS (why: benchmarked fastest)\nnameserver %s\nnameserver %s\n' "$w1" "$w2"
    } >"$tmp"
    apply_file "$backup_dir" "$(sys_p /etc/resolv.conf)" "$tmp" "fastest resolvers $w1 $w2" || return 1
  fi
  return 0
}

dns_verify() {
  local host="${SRV_TUNE_DNS_VERIFY_HOST:-$(dns_probe_host)}"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/health.sh"
  if health_dns "$host"; then
    return 0
  fi
  printf 'error: resolution of %s failed after DNS apply\n' "$host" >&2
  return 1
}
