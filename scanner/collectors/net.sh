#!/usr/bin/env bash
# Network collector (read-only, bounded network with timeouts).
# shellcheck shell=bash

collect_net() {
  local iface="unknown" mtu="unknown" ipv6="no" cc="unknown" qdisc="unknown"
  local dns="unknown" mirror="unknown" pubip="unknown"
  if command -v ip >/dev/null 2>&1; then
    iface="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || true)"
    if [[ -z "$iface" ]]; then iface="unknown"; fi
    if [[ "$iface" != "unknown" ]]; then
      mtu="$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || printf 'unknown')"
    fi
    if ip -6 addr show scope global 2>/dev/null | grep -q 'inet6'; then
      ipv6="yes"
    fi
    cc="$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || printf 'unknown')"
    if command -v tc >/dev/null 2>&1 && [[ "$iface" != "unknown" ]]; then
      qdisc="$(tc qdisc show dev "$iface" 2>/dev/null | head -n 1 | awk '{print $2}' || true)"
      if [[ -z "$qdisc" ]]; then qdisc="unknown"; fi
    fi
  fi
  if [[ -f /etc/resolv.conf ]]; then
    dns="$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed -E 's/,$//' || true)"
    if [[ -z "$dns" ]]; then dns="unknown"; fi
  fi
  if grep -rq 'deb822\|Types:' /etc/apt/sources.list.d/ 2>/dev/null; then
    mirror="deb822:$(ls /etc/apt/sources.list.d/ 2>/dev/null | tr '\n' ',')"
  elif [[ -f /etc/apt/sources.list ]]; then
    mirror="$(grep -E '^deb ' /etc/apt/sources.list 2>/dev/null | head -n 1 | awk '{print $2}' || true)"
    if [[ -z "$mirror" ]]; then mirror="unknown"; fi
  fi
  # Public IP: best-effort, 5s timeout, no failure if offline.
  if command -v curl >/dev/null 2>&1; then
    pubip="$(curl -sS --max-time 5 https://api.ipify.org 2>/dev/null || printf 'unknown')"
    if [[ -z "$pubip" ]]; then pubip="unknown"; fi
  fi
  printf 'IFACE=%s\nMTU=%s\nIPV6=%s\nCC=%s\nQDISC=%s\nDNS=%s\nMIRROR=%s\nPUBLIC_IP=%s\n' \
    "$iface" "$mtu" "$ipv6" "$cc" "$qdisc" "$dns" "$mirror" "$pubip"
}
