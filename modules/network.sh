#!/usr/bin/env bash
# network: BBR+fq when offered, TCP buffers from RAM and NIC speed, sanely
# sized queues; containers get drop-ins without live writes.
# NEVER: tcp_tw_recycle, ip_forward, rp_filter, accept_source_route
# (forwarding/filter knobs live only in the vpn-tunnel profile, P3b).
# Contract: network_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

# Knobs we refuse to ever emit (dangerous or removed from kernels).
network_banned() {
  case "$1" in
  *tcp_tw_recycle* | *ip_forward* | *rp_filter* | *accept_source_route*) return 0 ;;
  *) return 1 ;;
  esac
}

network_virt() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt 2>/dev/null || printf 'bare'
  elif [[ -f /.dockerenv ]]; then
    printf 'docker'
  else
    printf 'unknown'
  fi
}

network_is_container() {
  case "$(network_virt)" in
  docker | lxc | openvz | lxc-libvirt | systemd-nspawn | podman) return 0 ;;
  *) return 1 ;;
  esac
}

network_mem_kb() {
  awk '/^MemTotal:/{print $2}' "$(proc_p /proc/meminfo)" 2>/dev/null || printf '0'
}

network_nic_speed() {
  # Mbps; explicit override wins (tests), else fastest NIC, else 1000.
  if [[ -n "${SRV_TUNE_NIC_SPEED_MBPS:-}" ]]; then
    printf '%s\n' "$SRV_TUNE_NIC_SPEED_MBPS"
    return 0
  fi
  local s best=0 f
  for f in /sys/class/net/*/speed; do
    [[ -f "$f" ]] || continue
    case "$f" in
    */lo/*) continue ;;
    esac
    s="$(cat "$f" 2>/dev/null || printf '0')"
    [[ "$s" =~ ^[0-9]+$ ]] || s=0
    if [[ "$s" -gt "$best" ]]; then best="$s"; fi
  done
  if [[ "$best" -gt 0 ]]; then printf '%s\n' "$best"; else printf '1000\n'; fi
}

# network_key_ok <dotted-key> - the knob exists on this kernel.
network_key_ok() {
  local key="$1" rel
  rel="$(printf '%s' "$key" | tr '.' '/')"
  [[ -f "$(proc_p "/proc/sys/$rel")" ]]
}

network_bbr_ok() {
  local avail
  avail="$(cat "$(proc_p /proc/sys/net/ipv4/tcp_available_congestion_control)" 2>/dev/null || printf '')"
  case " $avail " in
  *' bbr '*) return 0 ;;
  *) return 1 ;;
  esac
}

# network_values - prints "key=value" lines this machine supports.
network_values() {
  local mem buf
  mem="$(network_mem_kb)"
  [[ "$mem" =~ ^[0-9]+$ ]] || mem=0
  # buf: RAM/16 clamped to 4MB..256MB (why: BDP headroom without waste).
  buf=$((mem * 1024 / 16))
  if [[ "$buf" -lt 4194304 ]]; then buf=4194304; fi
  if [[ "$buf" -gt 268435456 ]]; then buf=268435456; fi
  local lines=""
  lines="$lines
net.core.rmem_max=$buf
net.core.wmem_max=$buf
net.ipv4.tcp_rmem=4096 87380 $buf
net.ipv4.tcp_wmem=4096 65536 $buf
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192"
  if network_bbr_ok; then
    lines="$lines
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq"
  fi
  if network_key_ok net.ipv4.tcp_fastopen; then
    lines="$lines
net.ipv4.tcp_fastopen=3"
  fi
  if network_key_ok net.netfilter.nf_conntrack_max; then
    # ~7.5% of RAM / ~320B per entry (why: documented conntrack sizing).
    lines="$lines
net.netfilter.nf_conntrack_max=$((mem * 1024 * 75 / 1000 / 320))"
  fi
  local k v
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    if network_banned "$k"; then continue; fi
    if network_key_ok "$k"; then
      printf '%s=%s\n' "$k" "$v"
    fi
  done <<<"$lines"
}

network_detect() {
  printf 'VIRT=%s\nBBR=%s\n' "$(network_virt)" "$(network_bbr_ok && printf yes || printf no)"
  printf 'CC=%s\nQDISC=%s\n' \
    "$(cat "$(proc_p /proc/sys/net/ipv4/tcp_congestion_control)" 2>/dev/null || printf unknown)" \
    "$(cat "$(proc_p /proc/sys/net/core/default_qdisc)" 2>/dev/null || printf unknown)"
}

network_recommend() {
  local mem speed
  mem="$(network_mem_kb)"
  speed="$(network_nic_speed)"
  printf 'TCP buffers from %s kB RAM (why: BDP headroom, clamped 4-256MB)\n' "$mem"
  printf 'NIC speed %s Mbps (why: shapes buffer choice; override SRV_TUNE_NIC_SPEED_MBPS)\n' "$speed"
  if network_bbr_ok; then
    printf 'enable BBR+fq (why: kernel offers bbr, higher throughput)\n'
  else
    printf 'skip BBR (why: kernel lacks bbr; keeping %s)\n' "$(cat "$(proc_p /proc/sys/net/ipv4/tcp_congestion_control)" 2>/dev/null || printf current)"
  fi
  if network_is_container; then
    printf 'container detected (why: sysctls are read-only here; drop-in only, no live write)\n'
  fi
  printf 'somaxconn=4096, backlog=8192 (why: absorb bursts on small servers)\n'
  printf 'conntrack ~7.5%% RAM (why: ~320B per entry, only if nf_conntrack exists)\n'
  printf 'never tcp_tw_recycle/ip_forward/rp_filter (why: removed or profile-scoped)\n'
}

network_conf_path() {
  sys_p /etc/sysctl.d/00-srv-tune.conf
}

network_apply() {
  local backup_dir="$1" tmp
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  tmp="$(mktemp)"
  network_values >"$tmp"
  if grep -Eq 'tcp_tw_recycle|ip_forward|rp_filter|accept_source_route' "$tmp"; then
    printf 'error: banned knob in generated sysctl (refusing)\n' >&2
    rm -f "$tmp"
    return 1
  fi
  apply_file "$backup_dir" "$(network_conf_path)" "$tmp" "sysctl from RAM/NIC" || return 1
  if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]]; then
    printf 'note: TEST mode, skipping live sysctl load\n'
    return 0
  fi
  if network_is_container; then
    printf 'note: container, drop-in written for next boot, no live write\n'
    return 0
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl --system >/dev/null 2>&1 || printf 'warn: sysctl --system reported issues\n' >&2
  fi
  return 0
}

network_verify() {
  local f
  f="$(network_conf_path)"
  if [[ ! -f "$f" ]]; then
    printf 'error: sysctl drop-in missing: %s\n' "$f" >&2
    return 1
  fi
  if grep -Eq 'tcp_tw_recycle|ip_forward|rp_filter|accept_source_route' "$f"; then
    printf 'error: banned knob present in %s\n' "$f" >&2
    return 1
  fi
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]] || network_is_container; then
    return 0
  fi
  local k v cur want fail
  fail=0
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    cur="$(sysctl -n "$k" 2>/dev/null | tr -s ' \t' ' ' || printf '')"
    want="$(printf '%s' "$v" | tr -s ' \t' ' ')"
    if [[ "$cur" != "$want" ]]; then
      printf 'error: %s is %s, want %s\n' "$k" "$cur" "$want" >&2
      fail=1
    fi
  done <"$f"
  return "$fail"
}
