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
source "$(dirname "${BASH_SOURCE[0]}")/backup.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lock.sh"
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

# tunnel_ports - every valid Port value in the applied drop-in, in file order.
tunnel_ports() {
  local f p
  f="$(tunnel_dropin)"
  [[ -f "$f" ]] || return 0
  while IFS= read -r p; do
    if [[ "$p" =~ ^[1-9][0-9]*$ ]] && [[ "$p" -le 65535 ]]; then
      printf '%s\n' "$p"
    fi
  done < <(awk '$1 == "Port" {print $2}' "$f")
}

# tunnel_port - the operator's port: the LAST Port line (the renderer writes
# the default 22 first and the chosen port after it). Falls back to 22.
tunnel_port() {
  local p last=""
  while IFS= read -r p; do
    last="$p"
  done < <(tunnel_ports)
  printf '%s\n' "${last:-22}"
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

# tunnel_sessions_parse - ESTAB rows on any ssh Port: peer<TAB>pid per line.
tunnel_sessions_parse() {
  local bin="${SRV_TUNE_SS_BIN:-ss}" p re=""
  if [[ -z "${SRV_TUNE_SS_BIN:-}" ]] && ! command -v ss >/dev/null 2>&1; then
    printf 'error: ss not found (iproute2); sessions unavailable\n' >&2
    return 2
  fi
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    re="${re:+$re|}$p"
  done < <(tunnel_ports)
  re="${re:-22}"
  "$bin" -tnp 2>/dev/null | awk -v re="^:($re)$" '
    NR == 1 { next }
    $1 == "ESTAB" {
      n = split($4, a, ":")
      if ((":" a[n]) !~ re) next
      pid = ""
      if (match($0, /pid=[0-9]+/)) pid = substr($0, RSTART + 4, RLENGTH - 4)
      printf "%s\t%s\n", $5, pid
    }'
}

tunnel_sessions_text() {
  local rows
  rows="$(tunnel_sessions_parse)" || return $?
  [[ -z "$rows" ]] && return 0
  printf '%s\n' "$rows" | awk -F'\t' '{if ($2 == "") print $1; else printf "%s pid=%s\n", $1, $2}'
}

tunnel_sessions_json() {
  local rows out="" first=1 peer pid
  rows="$(tunnel_sessions_parse)" || return $?
  while IFS=$'\t' read -r peer pid; do
    [[ -z "$peer" ]] && continue
    [[ "$first" == "1" ]] || out+=","
    first=0
    out+="{\"peer\":\"$(tunnel_json_escape "$peer")\",\"pid\":\"$pid\"}"
  done <<<"$rows"
  printf '{"sessions":[%s]}\n' "$out"
  return 0
}

tunnel_sessions_count() {
  local out n="0"
  out="$(tunnel_sessions_json 2>/dev/null)" || {
    printf 'unavailable\n'
    return 0
  }
  n="$(printf '%s' "$out" | grep -o '"peer"' | wc -l || true)"
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

tunnel_require_root() {
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]]; then
    # TEST-only bypass: CI unit tests run unprivileged against SYSROOT.
    return 0
  fi
  if ! is_root; then
    printf 'error: run as root (key changes must be owned by the tunnel user)\n' >&2
    return 2
  fi
}

tunnel_home() {
  if [[ -n "${SRV_TUNE_TUNNEL_HOME:-}" ]]; then
    printf '%s\n' "$SRV_TUNE_TUNNEL_HOME"
    return 0
  fi
  local u home
  u="$(tunnel_user)"
  home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6 || true)"
  if [[ -z "$home" ]]; then
    printf 'error: tunnel user %s does not exist (apply the vpn-tunnel profile first)\n' "$u" >&2
    return 2
  fi
  printf '%s\n' "$home"
}

tunnel_keys_path() {
  local home
  home="$(tunnel_home)" || return $?
  printf '%s/.ssh/authorized_keys\n' "$home"
}

# tunnel_key_body <line> - base64 body, ignoring options and comment.
tunnel_key_body() {
  awk '{for (i=1;i<=NF;i++) if ($i ~ /^(ssh-|ecdsa-|sk-)/) {print $(i+1); exit}}' <<<"${1:-}"
}

tunnel_key_comment() {
  awk '{
    for (i=1;i<=NF;i++) {
      if ($i ~ /^(ssh-|ecdsa-|sk-)/) {
        for (j=i+2;j<=NF;j++) printf "%s%s", $j, (j<NF ? " " : "")
        exit
      }
    }
  }' <<<"${1:-}"
}

tunnel_key_rewrite_comment() {
  local line="${1:-}" comment="${2:-}"
  awk -v c="$comment" '{
    for (i=1;i<=NF;i++) {
      if ($i ~ /^(ssh-|ecdsa-|sk-)/) {
        pre = ""
        for (j=1;j<i;j++) pre = pre $j " "
        out = pre $i " " $(i+1)
        if (c != "") out = out " " c
        print out
        exit
      }
    }
  }' <<<"$line"
}

# tunnel_key_fp <line> - validates the line and prints its SHA256 fingerprint.
tunnel_key_fp() {
  local line="${1:-}" tmp fp
  tmp="$(mktemp)" || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  printf '%s\n' "$line" >"$tmp"
  fp="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2; exit}' || true)"
  rm -f "$tmp"
  if [[ -z "$fp" ]]; then
    printf 'error: not a valid OpenSSH public key\n' >&2
    return 1
  fi
  printf '%s\n' "$fp"
}

tunnel_audit() {
  local action="${1:-}" fp="${2:-}" comment="${3:-}" result="${4:-ok}"
  local state log actor src ts
  state="$(state_effective_dir 2>/dev/null || true)"
  [[ -n "$state" ]] || return 0
  log="$state/tunnel-actions.log"
  actor="${SRV_TUNE_ACTOR:-cli}"
  src="${SRV_TUNE_SRC:-}"
  if [[ -z "$src" ]]; then
    src="$(tty 2>/dev/null || true)"
    [[ -n "$src" ]] || src="cli"
  fi
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
  comment="${comment//$'\r'/ }"
  comment="${comment//$'\n'/ }"
  comment="${comment//\"/\'}"
  if ! printf 'ts=%s actor=%s action=%s fp=%s comment="%s" src=%s result=%s\n' \
    "$ts" "$actor" "$action" "$fp" "$comment" "$src" "$result" >>"$log" 2>/dev/null; then
    printf 'warn: could not write audit log %s\n' "$log" >&2
    return 0
  fi
  chmod 600 "$log" 2>/dev/null || true
  return 0
}

tunnel_keys_list() {
  local json=0 keys line fp rest type comment out="" first=1
  case "${1:-}" in
  "") ;;
  --json) json=1 ;;
  *)
    printf 'error: unknown keys list option: %s\n' "$1" >&2
    return 2
    ;;
  esac
  keys="$(tunnel_keys_path)" || return $?
  if [[ ! -s "$keys" ]]; then
    [[ "$json" == "1" ]] && printf '{"keys":[]}\n'
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    fp="${line#* }"
    fp="${fp%% *}"
    rest="${line#* * }"
    type="${rest##* (}"
    type="${type%)}"
    comment="${rest% (*}"
    if [[ "$json" == "1" ]]; then
      [[ "$first" == "1" ]] || out+=","
      first=0
      out+="{\"fp\":\"$(tunnel_json_escape "$fp")\",\"type\":\"$(tunnel_json_escape "$type")\",\"comment\":\"$(tunnel_json_escape "$comment")\"}"
    else
      printf '%s %s %s\n' "$fp" "$type" "$comment"
    fi
  done < <(ssh-keygen -lf "$keys" 2>/dev/null || true)
  [[ "$json" == "1" ]] && printf '{"keys":[%s]}\n' "$out"
  return 0
}

tunnel_keys_add() {
  local file="" comment="" have_comment=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --file)
      file="${2:-}"
      shift 2 || return 2
      ;;
    --comment)
      comment="${2:-}"
      have_comment=1
      shift 2 || return 2
      ;;
    -)
      file=""
      shift
      ;;
    *)
      printf 'error: unknown keys add option: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  tunnel_require_root || return $?
  local keys input line fp body newline newfp existing
  local state id bdir dir tmp rc
  keys="$(tunnel_keys_path)" || return $?
  if [[ -n "$file" && "$file" != "-" ]]; then
    if [[ ! -f "$file" ]]; then
      printf 'error: key file not found: %s\n' "$file" >&2
      return 1
    fi
    input="$(cat "$file")"
  else
    [[ -t 0 ]] && printf 'paste one OpenSSH public key: ' >&2
    input="$(cat)"
  fi
  local -a lines=()
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    lines+=("$line")
  done <<<"$input"
  if [[ ${#lines[@]} -eq 0 ]]; then
    printf 'error: no key provided\n' >&2
    tunnel_audit key-add "" "$comment" fail
    return 1
  fi
  if [[ ${#lines[@]} -gt 1 ]]; then
    printf 'error: add one key per call\n' >&2
    tunnel_audit key-add "" "$comment" fail
    return 1
  fi
  line="${lines[0]}"
  fp="$(tunnel_key_fp "$line")" || {
    tunnel_audit key-add "" "$comment" fail
    return 1
  }
  body="$(tunnel_key_body "$line")"
  if [[ -z "$body" ]]; then
    printf 'error: not a valid OpenSSH public key\n' >&2
    tunnel_audit key-add "$fp" "$comment" fail
    return 1
  fi
  lock_acquire || return 1
  (
    if [[ -f "$keys" ]]; then
      while IFS= read -r existing; do
        case "$existing" in
        '' | \#*) continue ;;
        esac
        if [[ "$(tunnel_key_body "$existing")" == "$body" ]]; then
          printf 'error: key already present (%s)\n' "$fp" >&2
          tunnel_audit key-add "$fp" "$comment" fail
          return 1
        fi
      done <"$keys"
    fi
    newline="$line"
    if [[ "$have_comment" == "1" ]]; then
      newline="$(tunnel_key_rewrite_comment "$line" "$comment")"
      newfp="$(tunnel_key_fp "$newline")" || {
        printf 'error: comment rewrite produced an invalid key\n' >&2
        tunnel_audit key-add "$fp" "$comment" fail
        return 1
      }
      [[ "$newfp" == "$fp" ]] || {
        printf 'error: comment rewrite changed the key\n' >&2
        return 1
      }
    fi
    state="$(state_effective_dir)" || return 1
    id="$(new_backup_id)"
    bdir="$state/backups/keys-$id"
    backup_file "$keys" "$bdir" || {
      printf 'error: could not back up %s\n' "$keys" >&2
      return 1
    }
    dir="$(dirname "$keys")"
    mkdir -p "$dir" || return 1
    chmod 700 "$dir" 2>/dev/null || true
    tmp="$(mktemp "$dir/.authorized_keys.XXXXXX")" || return 1
    if [[ -s "$keys" ]]; then
      cat "$keys" >>"$tmp"
      # Keep a trailing newline so the new key starts on its own line.
      [[ -n "$(tail -c 1 "$keys" 2>/dev/null)" ]] && printf '\n' >>"$tmp"
    fi
    printf '%s\n' "$newline" >>"$tmp"
    chmod 600 "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$keys"; then
      rm -f "$tmp"
      return 1
    fi
    chmod 600 "$keys" 2>/dev/null || true
    if is_root && id "$(tunnel_user)" >/dev/null 2>&1; then
      chown "$(tunnel_user):$(tunnel_user)" "$dir" "$keys" 2>/dev/null ||
        printf 'warn: chown failed for %s\n' "$keys" >&2
    fi
    tunnel_audit key-add "$fp" "$(tunnel_key_comment "$newline")" ok
    printf 'added %s (%s)\n' "$fp" "$(tunnel_key_comment "$newline")"
  )
  rc=$?
  lock_release
  return "$rc"
}

tunnel_keys_remove() {
  local fp="" keys state id bdir dir tmp line lfp found=0 rc
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --fp)
      fp="${2:-}"
      shift 2 || return 2
      ;;
    *)
      printf 'error: unknown keys remove option: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  if [[ ! "$fp" =~ ^SHA256:[A-Za-z0-9+/=]+$ ]]; then
    printf 'error: --fp needs a SHA256 fingerprint\n' >&2
    return 2
  fi
  tunnel_require_root || return $?
  keys="$(tunnel_keys_path)" || return $?
  lock_acquire || return 1
  (
    if [[ ! -s "$keys" ]]; then
      printf 'error: no keys for the tunnel user\n' >&2
      tunnel_audit key-remove "$fp" "" fail
      return 1
    fi
    dir="$(dirname "$keys")"
    tmp="$(mktemp "$dir/.authorized_keys.XXXXXX")" || return 1
    while IFS= read -r line; do
      case "$line" in
      '' | \#*)
        printf '%s\n' "$line" >>"$tmp"
        continue
        ;;
      esac
      lfp="$(tunnel_key_fp "$line" 2>/dev/null || true)"
      if [[ "$lfp" == "$fp" ]]; then
        found=1
        continue
      fi
      printf '%s\n' "$line" >>"$tmp"
    done <"$keys"
    if [[ "$found" != "1" ]]; then
      rm -f "$tmp"
      printf 'error: key not found: %s\n' "$fp" >&2
      tunnel_audit key-remove "$fp" "" fail
      return 1
    fi
    state="$(state_effective_dir)" || {
      rm -f "$tmp"
      return 1
    }
    id="$(new_backup_id)"
    bdir="$state/backups/keys-$id"
    if ! backup_file "$keys" "$bdir"; then
      rm -f "$tmp"
      printf 'error: could not back up %s\n' "$keys" >&2
      return 1
    fi
    chmod 600 "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$keys"; then
      rm -f "$tmp"
      return 1
    fi
    chmod 600 "$keys" 2>/dev/null || true
    if is_root && id "$(tunnel_user)" >/dev/null 2>&1; then
      chown "$(tunnel_user):$(tunnel_user)" "$dir" "$keys" 2>/dev/null ||
        printf 'warn: chown failed for %s\n' "$keys" >&2
    fi
    tunnel_audit key-remove "$fp" "" ok
    printf 'removed %s\n' "$fp"
  )
  rc=$?
  lock_release
  return "$rc"
}

tunnel_cmd_keys() {
  local sub="${1:-list}"
  case "$sub" in
  list)
    shift || true
    tunnel_keys_list "$@"
    ;;
  add)
    shift
    tunnel_keys_add "$@"
    ;;
  remove)
    shift
    tunnel_keys_remove "$@"
    ;;
  *)
    printf 'error: unknown keys subcommand: %s\n' "$sub" >&2
    return 2
    ;;
  esac
}

tunnel_cmd_access() {
  local sub="${1:-show}"
  case "$sub" in
  show)
    shift || true
    tunnel_access_show "$@"
    ;;
  set)
    shift
    tunnel_access_set "$@"
    ;;
  *)
    printf 'error: unknown access subcommand: %s\n' "$sub" >&2
    return 2
    ;;
  esac
}

tunnel_access_show() {
  local mode permit_open gw pt
  mode="$(tunnel_mode)"
  permit_open="$(tunnel_permit_open)"
  gw="$(tunnel_gateway_ports)"
  pt="$(tunnel_permit_tunnel)"
  case "${1:-}" in
  "")
    printf 'mode: %s\n' "$mode"
    printf 'permit_open: %s\n' "$permit_open"
    printf 'gateway_ports: %s\n' "$gw"
    printf 'permit_tunnel: %s\n' "$pt"
    ;;
  --json)
    printf '{"mode":"%s","permit_open":"%s","gateway_ports":%s,"permit_tunnel":%s}\n' \
      "$mode" "$(tunnel_json_escape "$permit_open")" \
      "$([[ "$gw" == "yes" ]] && printf true || printf false)" \
      "$([[ "$pt" == "yes" ]] && printf true || printf false)"
    ;;
  *)
    printf 'error: unknown access show option: %s\n' "$1" >&2
    return 2
    ;;
  esac
}

tunnel_validate_permit_open() {
  local v="${1:-}" entry host port
  [[ "$v" == "none" ]] && return 0
  if [[ -z "$v" ]]; then
    printf 'error: --permit-open must be none or host:port[,host:port]\n' >&2
    return 1
  fi
  local IFS=','
  for entry in $v; do
    host="${entry%%:*}"
    port="${entry##*:}"
    if [[ "$entry" != *:* ]] ||
      [[ ! "$host" =~ ^[A-Za-z0-9.*_-]+$ ]] ||
      [[ ! "$port" =~ ^[0-9]+$ ]] ||
      [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
      printf 'error: bad --permit-open entry: %s\n' "$entry" >&2
      return 1
    fi
  done
  return 0
}

tunnel_access_set() {
  local permit_open="" gateway="" have_po=0 have_gw=0 yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --permit-open)
      permit_open="${2:-}"
      have_po=1
      shift 2 || return 2
      ;;
    --gateway-ports)
      gateway="${2:-}"
      have_gw=1
      shift 2 || return 2
      ;;
    --yes)
      yes=1
      shift
      ;;
    *)
      printf 'error: unknown access set option: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  if [[ "$have_po" != "1" || "$have_gw" != "1" ]]; then
    printf 'error: access set needs --permit-open and --gateway-ports\n' >&2
    return 2
  fi
  case "$gateway" in
  yes | no) ;;
  *)
    printf 'error: --gateway-ports must be yes or no\n' >&2
    return 2
    ;;
  esac
  tunnel_validate_permit_open "$permit_open" || return 2
  tunnel_require_root || return $?
  if [[ "$(tunnel_mode)" != "TUNNEL" ]]; then
    printf 'error: not a tunnel server (apply --profile vpn-tunnel --with-ssh first)\n' >&2
    return 2
  fi
  # Preserve the applied port, user, and tun forwarding: losing them here
  # would silently change the server's network exposure.
  local port user tun=0
  port="$(tunnel_port)"
  user="$(tunnel_user)"
  [[ "$(tunnel_permit_tunnel)" == "yes" ]] && tun=1
  printf 'risk: this rewrites the TUNNEL sshd drop-in; bad values can cut your own access\n'
  printf 'risk: after the reload, prove a NEW session before the guard expires\n'
  if [[ "$yes" != "1" ]]; then
    ui_type_confirm 'Type SSH-YES to rewrite the tunnel access policy: ' "SSH-YES" || {
      printf 'aborted\n'
      return 1
    }
  fi
  # Our own typed confirm replaces the module's second gate for this one
  # explicit edit; the guard below is untouched. The knobs live in a
  # subshell: the TUI calls this from a long-lived shell, and a leaked
  # SRV_TUNE_ASSUME_YES would auto-accept every later prompt.
  (
    export SRV_TUNE_ASSUME_YES=1
    export SRV_TUNE_SSH_MODE=TUNNEL
    export SRV_TUNE_TUNNEL_USER="$user"
    export SRV_TUNE_SSH_PORT="$port"
    export SRV_TUNE_PERMIT_OPEN="$permit_open"
    export SRV_TUNE_TUNNEL_GATEWAY=0
    [[ "$gateway" == "yes" ]] && export SRV_TUNE_TUNNEL_GATEWAY=1
    if [[ "$tun" == "1" ]]; then
      export SRV_TUNE_TUNNEL_MODE=tun
    else
      unset SRV_TUNE_TUNNEL_MODE
    fi
    export SRV_TUNE_WITH_SSH=1
    export SRV_TUNE_PROFILE=vpn-tunnel
    lock_acquire || exit 1
    rc=0
    run_apply vpn-tunnel ssh || rc=$?
    lock_release
    exit "$rc"
  )
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
  command -v python3 >/dev/null 2>&1 || {
    printf 'error: python3 not found; the web panel needs python3 (the TUI works without it)\n' >&2
    return 2
  }
  local port="${SRV_TUNE_TUNNEL_WEB_PORT:-8787}" bind="127.0.0.1"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --port)
      port="${2:-}"
      shift 2 || return 2
      ;;
    --bind)
      bind="${2:-}"
      shift 2 || return 2
      ;;
    *)
      printf 'error: unknown web option: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
    printf 'error: --port must be 1-65535\n' >&2
    return 2
  fi
  local state bin
  state="$(state_effective_dir)" || return 1
  mkdir -p "$state/web" || return 1
  chmod 700 "$state/web" 2>/dev/null || true
  bin="${SRV_TUNE_BIN:-}"
  if [[ -z "$bin" ]]; then
    if command -v srv-tune >/dev/null 2>&1; then
      bin="srv-tune"
    else
      bin="$SRV_TUNE_ROOT/optimizer.sh"
    fi
  fi
  python3 "$SRV_TUNE_ROOT/web/tunnel_web.py" \
    --port "$port" --bind "$bind" --state-dir "$state" \
    --bin "$bin" --lang "$(srv_tune_lang)"
}

tunnel_tui() {
  if [[ ! -t 0 ]]; then
    tunnel_status_text
    return 0
  fi
  local choice
  while true; do
    printf '\n'
    tunnel_status_text
    choice="$(ui_menu "$(t tunnel_title)" refresh refresh keys access sessions quit)"
    case "$choice" in
    refresh) continue ;;
    quit) return 0 ;;
    keys) tunnel_tui_keys ;;
    access) tunnel_tui_access ;;
    sessions)
      tunnel_sessions_text
      printf 'press Enter to continue... '
      IFS= read -r _ || true
      ;;
    esac
  done
}

tunnel_tui_keys() {
  local choice line tmp rc
  while true; do
    choice="$(ui_menu "$(t tunnel_keys)" list list add remove back)"
    case "$choice" in
    back) return 0 ;;
    list) tunnel_keys_list ;;
    add)
      printf 'paste one OpenSSH public key: '
      IFS= read -r line || return 0
      tmp="$(mktemp)" || return 1
      printf '%s\n' "$line" >"$tmp"
      rc=0
      SRV_TUNE_ACTOR=tui tunnel_keys_add --file "$tmp" || rc=$?
      rm -f "$tmp"
      ;;
    remove)
      tunnel_keys_list
      printf 'fingerprint to remove (SHA256:...): '
      IFS= read -r line || return 0
      SRV_TUNE_ACTOR=tui tunnel_keys_remove --fp "$line" || rc=$?
      ;;
    esac
  done
}

tunnel_tui_access() {
  local choice po gw
  tunnel_access_show
  choice="$(ui_menu "$(t tunnel_access)" back edit back)"
  [[ "$choice" == "back" ]] && return 0
  printf '%s [%s]: ' "$(t tunnel_permits)" "$(tunnel_permit_open)"
  IFS= read -r po || return 0
  [[ -n "$po" ]] || po="$(tunnel_permit_open)"
  printf '%s [%s]: ' "$(t tunnel_gateway)" "$(tunnel_gateway_ports)"
  IFS= read -r gw || return 0
  [[ -n "$gw" ]] || gw="$(tunnel_gateway_ports)"
  if [[ "$gw" != "yes" && "$gw" != "no" ]]; then
    printf 'error: gateway must be yes or no\n'
    return 0
  fi
  printf '%s\n' "$(t tunnel_risk)"
  ui_type_confirm "$(t tunnel_confirm)" "SSH-YES" || {
    printf '%s\n' "$(t aborted)"
    return 0
  }
  SRV_TUNE_ACTOR=tui tunnel_access_set --permit-open "$po" --gateway-ports "$gw" --yes
  return 0
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
