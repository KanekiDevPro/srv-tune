#!/usr/bin/env bash
# SSH collector (read-only, parses effective config).
# shellcheck shell=bash

collect_ssh() {
  local port="22" root="unknown" pass="unknown" sock="no" ok="unknown"
  if command -v sshd >/dev/null 2>&1; then
    # sshd -T prints effective config; needs root. Best-effort.
    local t
    t="$(sshd -T 2>/dev/null || printf '')"
    if [[ -n "$t" ]]; then
      port="$(printf '%s' "$t" | grep -Ei '^port ' | head -n 1 | awk '{print $2}' || true)"
      root="$(printf '%s' "$t" | grep -Ei '^permitrootlogin ' | head -n 1 | awk '{print $2}' || true)"
      pass="$(printf '%s' "$t" | grep -Ei '^passwordauthentication ' | head -n 1 | awk '{print $2}' || true)"
      if [[ -z "$port" ]]; then port="22"; fi
    fi
    sshd -t 2>/dev/null && ok="yes" || ok="no"
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep -q 'ssh' && sock="listening" || sock="no"
  fi
  # ssh.socket detection (systemd).
  if systemctl list-sockets 2>/dev/null | grep -q 'ssh.socket'; then
    sock="socket-active"
  fi
  printf 'SSH_PORT=%s\nSSH_ROOT=%s\nSSH_PASS=%s\nSSH_LISTEN=%s\nSSH_OK=%s\n' \
    "$port" "$root" "$pass" "$sock" "$ok"
}
