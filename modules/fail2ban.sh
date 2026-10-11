#!/usr/bin/env bash
# fail2ban: jail.d drop-in with the session source in ignoreip, backend=systemd.
# Never jails the operator's current address. Best-effort service handling.
# Contract: fail2ban_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

fail2ban_src() {
  local c="${SSH_CONNECTION:-}"
  if [[ -n "$c" ]]; then
    printf '%s\n' "${c%% *}"
  else
    printf '127.0.0.1\n'
  fi
}

fail2ban_is_live() {
  [[ "${SRV_TUNE_TEST:-0}" != "1" && "${SRV_TUNE_SYSROOT:-/}" == "/" ]]
}

fail2ban_detect() {
  if command -v fail2ban-client >/dev/null 2>&1; then
    printf 'PRESENT=yes\n'
  else
    printf 'PRESENT=no\n'
  fi
  printf 'SRC=%s\n' "$(fail2ban_src)"
}

fail2ban_recommend() {
  printf 'ignoreip always includes %s (why: never jail this session)\n' "$(fail2ban_src)"
  printf 'backend=systemd, sshd jail on, sane bantime/findtime/maxretry (why: brute-force throttle)\n'
}

fail2ban_apply() {
  local backup_dir="$1" tmp src
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  src="$(fail2ban_src)"
  tmp="$(mktemp)"
  {
    printf '# srv-tune fail2ban (why: computed, see recommend)\n'
    printf '[DEFAULT]\nbackend = systemd\nbantime = 1h\nfindtime = 10m\nmaxretry = 5\n'
    printf 'ignoreip = 127.0.0.1/8 %s\n' "$src"
    printf '\n[sshd]\nenabled = true\nport = %s\nmaxretry = 5\n' "${SRV_TUNE_SSH_PORT:-22}"
  } >"$tmp"
  apply_file "$backup_dir" "$(sys_p /etc/fail2ban/jail.d/00-srv-tune.local)" "$tmp" "fail2ban sshd jail" || return 1
  if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  if ! fail2ban_is_live; then
    printf 'note: sandboxed, fail2ban reload skipped\n'
    return 0
  fi
  if command -v fail2ban-client >/dev/null 2>&1; then
    fail2ban-client ping >/dev/null 2>&1 || printf 'warn: fail2ban daemon not answering\n' >&2
    fail2ban-client reload >/dev/null 2>&1 || printf 'warn: fail2ban reload failed\n' >&2
  else
    printf 'note: fail2ban not installed; config staged for later\n'
  fi
  return 0
}

fail2ban_verify() {
  local f src
  f="$(sys_p /etc/fail2ban/jail.d/00-srv-tune.local)"
  src="$(fail2ban_src)"
  if [[ ! -f "$f" ]]; then
    printf 'error: fail2ban drop-in missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q 'backend = systemd' "$f" || {
    printf 'error: backend=systemd missing in %s\n' "$f" >&2
    return 1
  }
  grep -qF "$src" "$f" || {
    printf 'error: session source %s missing from ignoreip\n' "$src" >&2
    return 1
  }
  return 0
}
