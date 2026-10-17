#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tunnel UI core: status/sessions/keys/access over the applied TUNNEL
# drop-in. The TUI and the web panel both call these functions.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_TUNNEL_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_TUNNEL_SOURCED=1

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/modules.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/state.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/i18n.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

tunnel_usage() {
  printf 'usage: srv-tune tunnel [status [--json]]\n'
  printf '       srv-tune tunnel keys list|add|remove\n'
  printf '       srv-tune tunnel access show|set\n'
  printf '       srv-tune tunnel sessions [--json]\n'
  printf '       srv-tune tunnel web [--port N] [--bind ADDR]\n'
  printf '       srv-tune tunnel            (interactive TUI; no tty: status)\n'
}

# tunnel_dropin - applied ssh drop-in path (sources the ssh module once).
tunnel_dropin() {
  if ! command -v ssh_dropin_path >/dev/null 2>&1; then
    module_load ssh >/dev/null 2>&1 || true
  fi
  ssh_dropin_path
}

tunnel_mode() {
  local f first
  f="$(tunnel_dropin)"
  if [[ ! -f "$f" ]]; then
    printf 'absent\n'
    return 0
  fi
  first="$(head -n1 "$f" 2>/dev/null || true)"
  case "$first" in
  *TUNNEL*) printf 'TUNNEL\n' ;;
  *ADMIN*) printf 'ADMIN\n' ;;
  *CUSTOM*) printf 'CUSTOM\n' ;;
  *) printf 'absent\n' ;;
  esac
}

# tunnel_dropin_value <keyword> [second] - first matching value.
tunnel_dropin_value() {
  local f kw="${1:-}" second="${2:-}"
  f="$(tunnel_dropin)"
  [[ -f "$f" ]] || return 1
  if [[ -n "$second" ]]; then
    awk -v k="$kw" -v s="$second" '$1==k && $2==s {print $3; exit}' "$f"
  else
    awk -v k="$kw" '$1==k {print $2; exit}' "$f"
  fi
}

tunnel_port() {
  local p
  p="$(tunnel_dropin_value Port 2>/dev/null || true)"
  if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 && "$p" -le 65535 ]]; then
    printf '%s\n' "$p"
  else
    printf '22\n'
  fi
}

tunnel_user() {
  local u
  u="$(tunnel_dropin_value Match User 2>/dev/null || true)"
  [[ -n "$u" ]] || u="${SRV_TUNE_TUNNEL_USER:-tunnel}"
  printf '%s\n' "$u"
}

tunnel_permit_open() {
  local v
  v="$(tunnel_dropin_value PermitOpen 2>/dev/null || true)"
  [[ -n "$v" ]] || v="none"
  printf '%s\n' "$v"
}

tunnel_gateway_ports() {
  local v
  v="$(tunnel_dropin_value GatewayPorts 2>/dev/null || true)"
  case "$v" in
  yes) printf 'yes\n' ;;
  *) printf 'no\n' ;;
  esac
}

tunnel_permit_tunnel() {
  local v
  v="$(tunnel_dropin_value PermitTunnel 2>/dev/null || true)"
  case "$v" in
  yes) printf 'yes\n' ;;
  *) printf 'no\n' ;;
  esac
}

tunnel_ip_forward() {
  local f
  f="$(sys_p /etc/sysctl.d/00-srv-tune-tun.conf)"
  if [[ -f "$f" ]] && grep -q '^net.ipv4.ip_forward=1$' "$f" 2>/dev/null; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

tunnel_sessions_available() {
  [[ -n "${SRV_TUNE_SS_BIN:-}" ]] || command -v ss >/dev/null 2>&1
}

# tunnel_sessions_json - real parsing lands with the sessions task.
tunnel_sessions_json() {
  printf '{"sessions":[]}\n'
}

tunnel_sessions_text() {
  return 0
}

tunnel_sessions_count() {
  local n="0"
  if ! tunnel_sessions_available; then
    printf 'unavailable\n'
    return 0
  fi
  n="$(tunnel_sessions_json | grep -o '"peer"' | wc -l || true)"
  printf '%d\n' "$((n + 0))"
}

tunnel_status_text() {
  local dropin present
  dropin="$(tunnel_dropin)"
  present="absent"
  [[ -f "$dropin" ]] && present="present"
  printf 'mode: %s\n' "$(tunnel_mode)"
  printf 'port: %s\n' "$(tunnel_port)"
  printf 'user: %s\n' "$(tunnel_user)"
  printf 'permit_open: %s\n' "$(tunnel_permit_open)"
  printf 'gateway_ports: %s\n' "$(tunnel_gateway_ports)"
  printf 'permit_tunnel: %s\n' "$(tunnel_permit_tunnel)"
  printf 'ip_forward: %s\n' "$(tunnel_ip_forward)"
  printf 'dropin: %s (%s)\n' "$dropin" "$present"
  printf 'sessions: %s\n' "$(tunnel_sessions_count)"
}

tunnel_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

tunnel_status_json() {
  local mode port user permit_open dropin present gw pt ipf sess
  mode="$(tunnel_mode)"
  port="$(tunnel_port)"
  user="$(tunnel_json_escape "$(tunnel_user)")"
  permit_open="$(tunnel_json_escape "$(tunnel_permit_open)")"
  dropin="$(tunnel_json_escape "$(tunnel_dropin)")"
  present=false
  [[ -f "$(tunnel_dropin)" ]] && present=true
  gw=false
  [[ "$(tunnel_gateway_ports)" == "yes" ]] && gw=true
  pt=false
  [[ "$(tunnel_permit_tunnel)" == "yes" ]] && pt=true
  ipf=false
  [[ "$(tunnel_ip_forward)" == "yes" ]] && ipf=true
  sess="$(tunnel_sessions_count)"
  [[ "$sess" =~ ^[0-9]+$ ]] || sess=null
  printf '{"mode":"%s","port":"%s","user":"%s","permit_open":"%s","gateway_ports":%s,"permit_tunnel":%s,"ip_forward":%s,"dropin":"%s","dropin_present":%s,"sessions":%s}\n' \
    "$mode" "$port" "$user" "$permit_open" "$gw" "$pt" "$ipf" "$dropin" "$present" "$sess"
}

tunnel_cmd_status() {
  case "${1:-}" in
  "") tunnel_status_text ;;
  --json) tunnel_status_json ;;
  *)
    printf 'error: unknown status option: %s\n' "$1" >&2
    return 2
    ;;
  esac
}

tunnel_cmd_keys() {
  printf 'error: tunnel keys is not implemented yet\n' >&2
  return 2
}

tunnel_cmd_access() {
  printf 'error: tunnel access is not implemented yet\n' >&2
  return 2
}

tunnel_cmd_sessions() {
  case "${1:-}" in
  "") tunnel_sessions_text ;;
  --json) tunnel_sessions_json ;;
  *)
    printf 'error: unknown sessions option: %s\n' "$1" >&2
    return 2
    ;;
  esac
}

tunnel_cmd_web() {
  printf 'error: tunnel web is not implemented yet\n' >&2
  return 2
}

tunnel_tui() {
  if [[ ! -t 0 ]]; then
    tunnel_status_text
    return 0
  fi
  # Menu lands with the TUI task; status is the safe default until then.
  tunnel_status_text
}

tunnel_main() {
  local sub="${1:-}"
  case "$sub" in
  "" | tui) tunnel_tui ;;
  status)
    shift
    tunnel_cmd_status "$@"
    ;;
  keys)
    shift
    tunnel_cmd_keys "$@"
    ;;
  access)
    shift
    tunnel_cmd_access "$@"
    ;;
  sessions)
    shift
    tunnel_cmd_sessions "$@"
    ;;
  web)
    shift
    tunnel_cmd_web "$@"
    ;;
  -h | --help) tunnel_usage ;;
  *)
    printf 'error: unknown tunnel subcommand: %s\n' "$sub" >&2
    tunnel_usage >&2
    return 2
    ;;
  esac
}
