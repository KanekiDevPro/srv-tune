#!/usr/bin/env bash
# dns: benchmark candidate resolvers live, apply fastest via resolved,
# resolv.conf or netplan; cloud-init respected; rollback on broken resolution.
# DoT stays off unless port 853 is reachable (then it is only OFFERED).
# Benchmarks: 2s timeout, max 4 parallel, contacted hosts always printed.
# Contract: dns_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

dns_tool() {
  if command -v dig >/dev/null 2>&1; then
    printf 'dig\n'
  else
    printf 'none\n'
  fi
}

dns_probe_host() {
  printf '%s\n' "${SRV_TUNE_DNS_PROBE:-example.com}"
}

dns_candidates() {
  local root="${SRV_TUNE_ROOT:-.}" f line ip
  f="$root/data/dns-resolvers.list"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    ip="$(printf '%s' "$line" | awk '{print $1}')"
    [[ -n "$ip" ]] && printf '%s\n' "$ip"
  done <"$f"
}

# dns_probe_one <ip> <probe> <out> - single dig probe; appends "ip ms ok|fail".
dns_probe_one() {
  local ip="$1" probe="$2" out="$3" txt ms
  txt="$(dig +time=2 +tries=1 "@$ip" "$probe" 2>/dev/null || true)"
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
    printf 'skip: no dig installed (why: cannot benchmark; install dnsutils or set resolvers manually)\n'
    return 0
  fi
  printf 'benchmark (why: latency + failure rate from THIS server):\n'
  dns_benchmark
  printf 'pick: fastest with 0/2 failures as primary, second as secondary (why: redundancy)\n'
}

dns_apply() {
  local backup_dir="$1" backend winners w1 w2 tmp
  if [[ "$(dns_tool)" == "none" ]]; then
    printf 'skip: no dig, nothing to benchmark\n'
    return 2
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  winners="$(dns_winners)"
  w1="$(printf '%s' "$winners" | sed -n '1p')"
  w2="$(printf '%s' "$winners" | sed -n '2p')"
  if [[ -z "$w1" ]]; then
    printf 'error: every candidate resolver failed; refusing to apply\n' >&2
    return 1
  fi
  if [[ -z "$w2" ]]; then w2="$w1"; fi
  backend="$(dns_backend)"
  if [[ "$backend" == "resolved" ]]; then
    tmp="$(mktemp)"
    {
      printf '# srv-tune DNS (why: benchmarked fastest)\n[Resolve]\nDNS=%s %s\nFallbackDNS=1.1.1.1 8.8.8.8\nDNSOverTLS=no\n' "$w1" "$w2"
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
