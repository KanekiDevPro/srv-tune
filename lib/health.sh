#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Post-module health checks. Exit codes: 0 = healthy, 1 = broken, 2 = skipped
# (tool missing; caller decides). Read-only unless stated.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_HEALTH_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_HEALTH_SOURCED=1

# health_dns [host] - resolution works (rollback if it fails after DNS apply).
health_dns() {
  local host="${1:-example.com}"
  command -v getent >/dev/null 2>&1 || return 2
  getent hosts "$host" >/dev/null 2>&1
}

# health_sshd - effective sshd config parses (run before every reload).
health_sshd() {
  command -v sshd >/dev/null 2>&1 || return 2
  sshd -t 2>/dev/null
}

# health_port <port> - something listens on TCP port (after SSH/firewall).
health_port() {
  local port="$1"
  command -v ss >/dev/null 2>&1 || return 2
  ss -tlnp 2>/dev/null | grep -q ":${port} "
}

# health_ssh_owner - prints which unit owns port 22: socket|service|none.
# P3 reloads must branch on this (Ubuntu socket vs Debian service).
health_ssh_owner() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-sockets 2>/dev/null | grep -q 'ssh.socket'; then
    printf 'socket\n'
  elif command -v systemctl >/dev/null 2>&1 && systemctl is-active ssh.service >/dev/null 2>&1; then
    printf 'service\n'
  else
    printf 'none\n'
  fi
}

# health_mirror_uri <uri> - one configured mirror answers (bounded, curl).
health_mirror_uri() {
  local uri="$1"
  command -v curl >/dev/null 2>&1 || return 2
  curl -sS -o /dev/null --max-time 10 "$uri" 2>/dev/null
}
