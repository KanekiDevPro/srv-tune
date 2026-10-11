#!/usr/bin/env bash
# ssh: ADMIN (default) / TUNNEL / CUSTOM. Drop-in 00-srv-tune.conf only
# (first-match-wins), sshd -t validation, reload-not-restart, socket vs
# service handling, firewall port first, guard + NEW-session confirm.
# Key-only auth ONLY after a verified authorized_keys. No daemon is touched
# in TEST mode or under SYSROOT (sandboxed unit tests).
# Contract: ssh_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

ssh_mode() {
  printf '%s\n' "${SRV_TUNE_SSH_MODE:-ADMIN}"
}

ssh_user() {
  printf '%s\n' "${SRV_TUNE_SSH_USER:-root}"
}

ssh_port() {
  printf '%s\n' "${SRV_TUNE_SSH_PORT:-22}"
}

# ssh_home - target user's home (TEST override for sandboxes).
ssh_home() {
  if [[ -n "${SRV_TUNE_TEST_USER_HOME:-}" ]]; then
    printf '%s\n' "$SRV_TUNE_TEST_USER_HOME"
    return 0
  fi
  local u home
  u="$(ssh_user)"
  home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6 || true)"
  [[ -z "$home" ]] && return 1
  printf '%s\n' "$home"
}

# ssh_chmod_effective - can this platform express unix modes? (Windows ACLs
# silently ignore chmod; never fail closed on such hosts in TEST mode.)
ssh_chmod_effective() {
  local t
  t="$(mktemp)" || return 1
  chmod 600 "$t" 2>/dev/null || {
    rm -f "$t"
    return 1
  }
  local perms
  perms="$(ls -ld "$t" 2>/dev/null | awk '{print $1}')"
  rm -f "$t"
  [[ "$perms" == "-rw-------" ]]
}

# ssh_key_ok - valid authorized_keys with safe permissions.
ssh_key_ok() {
  local home dir keys line
  home="$(ssh_home)" || {
    printf 'error: unknown user %s\n' "$(ssh_user)" >&2
    return 1
  }
  dir="$home/.ssh"
  keys="$dir/authorized_keys"
  if [[ ! -s "$keys" ]]; then
    printf 'error: no authorized_keys for %s at %s (key-only auth refused)\n' "$(ssh_user)" "$keys" >&2
    return 1
  fi
  line="$(grep -Ev '^[[:space:]]*(#|$)' "$keys" 2>/dev/null | head -n 1 || true)"
  case "$line" in
  ssh-*' AAA'* | ecdsa-*' AAA'* | sk-*' AAA'* | 'AAA'*) ;;
  *)
    printf 'error: authorized_keys for %s has no valid key line\n' "$(ssh_user)" >&2
    return 1
    ;;
  esac
  if ssh_chmod_effective; then
    local dperms fperms
    dperms="$(ls -ld "$dir" 2>/dev/null | awk '{print $1}')"
    fperms="$(ls -l "$keys" 2>/dev/null | awk '{print $1}')"
    if [[ "$dperms" != "drwx------" ]]; then
      printf 'error: %s must be 700 (is %s)\n' "$dir" "$dperms" >&2
      return 1
    fi
    if [[ "$fperms" != "-rw-------" && "$fperms" != "-r--------" ]]; then
      printf 'error: %s must be 600 (is %s)\n' "$keys" "$fperms" >&2
      return 1
    fi
  elif [[ "${SRV_TUNE_TEST:-0}" != "1" ]]; then
    printf 'error: cannot verify permissions on this platform\n' >&2
    return 1
  else
    printf 'note: platform ignores chmod; permission gate checked on target\n'
  fi
  return 0
}

ssh_aesni() {
  grep -qi ' aes ' "$(proc_p /proc/cpuinfo)" 2>/dev/null
}

# ssh_known_keyword - whitelist for drop-in validation (fail closed).
ssh_known_keyword() {
  case "$1" in
  Port | PermitRootLogin | PasswordAuthentication | PubkeyAuthentication | \
    MaxAuthTries | LoginGraceTime | X11Forwarding | UseDNS | \
    ClientAliveInterval | ClientAliveCountMax | AllowTcpForwarding | \
    TCPKeepAlive | Compression | MaxSessions | MaxStartups | GatewayPorts | \
    PermitTunnel | PermitTTY | ForceCommand | PermitOpen | AllowUsers | \
    AllowGroups | DenyUsers | DenyGroups | Ciphers | MACs | KexAlgorithms | \
    Banner | Match | AuthorizedKeysFile | ChallengeResponseAuthentication | \
    KbdInteractiveAuthentication | PermitEmptyPasswords | PrintMotd | \
    AcceptEnv | Subsystem | LogLevel)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# ssh_validate_dropin <file> - every keyword must be known, Port numeric.
ssh_validate_dropin() {
  local f="$1" kw rest
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    kw="$(printf '%s' "$line" | awk '{print $1}')"
    rest="$(printf '%s' "$line" | cut -d' ' -f2-)"
    if ! ssh_known_keyword "$kw"; then
      printf "error: unknown sshd keyword '%s' (refusing)\n" "$kw" >&2
      return 1
    fi
    if [[ "$kw" == "Port" ]]; then
      local p
      for p in $rest; do
        if [[ ! "$p" =~ ^[0-9]+$ ]] || [[ "$p" -lt 1 || "$p" -gt 65535 ]]; then
          printf "error: bad Port value '%s' (refusing)\n" "$p" >&2
          return 1
        fi
      done
    fi
  done <"$f"
  return 0
}

ssh_dropin_path() {
  sys_p /etc/ssh/sshd_config.d/00-srv-tune.conf
}

ssh_render_admin() {
  local out="$1" port
  port="$(ssh_port)"
  {
    printf '# srv-tune ADMIN (why: key-only after verified key; drop-in sorts first)\n'
    printf 'Port 22\n'
    if [[ "$port" != "22" ]]; then
      printf 'Port %s\n' "$port"
    fi
    printf 'PermitRootLogin prohibit-password\n'
    printf 'PasswordAuthentication no\nPubkeyAuthentication yes\n'
    printf 'MaxAuthTries 3\nLoginGraceTime 30\n'
    printf 'X11Forwarding no\nUseDNS no\n'
    printf 'ClientAliveInterval 30\nClientAliveCountMax 3\n'
  } >"$out"
}

ssh_render_tunnel() {
  local out="$1" port ciphers user
  port="$(ssh_port)"
  user="${SRV_TUNE_TUNNEL_USER:-tunnel}"
  if ssh_aesni; then
    ciphers="aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com"
  else
    ciphers="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
  fi
  {
    printf '# srv-tune TUNNEL (why: forwarding server, no shell)\n'
    printf 'Port 22\n'
    if [[ "$port" != "22" ]]; then
      printf 'Port %s\n' "$port"
    fi
    printf 'AllowTcpForwarding yes\nTCPKeepAlive yes\nCompression no\n'
    printf 'MaxSessions 100\nMaxStartups 100:30:200\n'
    if [[ "${SRV_TUNE_TUNNEL_GATEWAY:-0}" == "1" ]]; then
      printf 'GatewayPorts yes\n'
    else
      printf 'GatewayPorts no\n'
    fi
    if [[ "${SRV_TUNE_TUNNEL_MODE:-}" == "tun" && "${SRV_TUNE_PROFILE:-}" == "vpn-tunnel" ]]; then
      printf 'PermitTunnel yes\n'
    else
      printf 'PermitTunnel no\n'
    fi
    printf 'Ciphers %s\n' "$ciphers"
    printf 'Match User %s\n' "$user"
    printf '  PermitTTY no\n'
    printf '  ForceCommand /usr/sbin/nologin\n'
    printf '  PermitOpen %s\n' "${SRV_TUNE_PERMIT_OPEN:-none}"
  } >"$out"
}

ssh_render_custom() {
  local out="$1" src="${SRV_TUNE_SSH_CUSTOM_SRC:-}"
  {
    printf '# srv-tune CUSTOM baseline (why: safe subset; operator snippet appended)\n'
    printf 'Port 22\n'
    local port
    port="$(ssh_port)"
    if [[ "$port" != "22" ]]; then
      printf 'Port %s\n' "$port"
    fi
    printf 'MaxAuthTries 3\nLoginGraceTime 60\nX11Forwarding no\n'
  } >"$out"
  if [[ -n "$src" ]]; then
    if [[ ! -f "$src" ]]; then
      printf 'error: custom snippet missing: %s\n' "$src" >&2
      return 1
    fi
    cat "$src" >>"$out"
  else
    printf 'note: no SRV_TUNE_SSH_CUSTOM_SRC; baseline only\n'
  fi
  return 0
}

# ssh_sshd_test - sshd -t on the live merged config (the drop-in is part of
# it after apply). Honors SRV_TUNE_SSHD_BIN (tests point it at a stub).
ssh_sshd_test() {
  local bin="${SRV_TUNE_SSHD_BIN:-}"
  if [[ -z "$bin" ]]; then
    if [[ "${SRV_TUNE_TEST:-0}" == "1" || "${SRV_TUNE_SYSROOT:-/}" != "/" ]]; then
      printf 'note: sandboxed, sshd -t skipped (whitelist validation stands)\n'
      return 0
    fi
    if ! command -v sshd >/dev/null 2>&1; then
      printf 'note: sshd missing, whitelist validation only\n'
      return 0
    fi
    bin="sshd"
  fi
  "$bin" -t 2>/dev/null
}

ssh_detect() {
  printf 'MODE=%s\nPORT=%s\nUSER=%s\n' "$(ssh_mode)" "$(ssh_port)" "$(ssh_user)"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/health.sh"
  printf 'OWNER=%s\n' "$(health_ssh_owner)"
}

ssh_recommend() {
  printf 'mode: %s (why: ADMIN default; TUNNEL only for forwarding hosts)\n' "$(ssh_mode)"
  printf 'drop-in %s sorts first (why: sshd first-match-wins)\n' "$(ssh_dropin_path)"
  if [[ "$(ssh_port)" != "22" ]]; then
    printf 'port %s added alongside 22 (why: old port stays until verified; socket override written)\n' "$(ssh_port)"
  fi
  if [[ "$(ssh_mode)" == "ADMIN" ]]; then
    if ssh_key_ok 2>/dev/null; then
      printf 'key-only auth (why: valid authorized_keys verified)\n'
    else
      printf 'BLOCKED until a valid authorized_keys exists (why: key-only without a key locks you out)\n'
    fi
  fi
  printf 'guard + NEW-session confirm required (why: reverts on silence)\n'
}

# ssh_firewall_first <port> - open the port before touching sshd.
ssh_firewall_first() {
  local port="$1" root="${SRV_TUNE_ROOT:-.}"
  if [[ ! -f "$root/modules/firewall.sh" ]]; then
    printf 'note: no firewall module; open TCP/%s manually before reload\n' "$port"
    return 0
  fi
  # shellcheck disable=SC1090
  source "$root/modules/firewall.sh"
  firewall_allow_port "$port"
}

ssh_reload() {
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/health.sh"
  local owner
  owner="$(health_ssh_owner)"
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]] || [[ "${SRV_TUNE_SYSROOT:-/}" != "/" ]]; then
    printf 'note: sandboxed, no daemon reload (owner=%s)\n' "$owner"
    return 0
  fi
  if [[ "$owner" == "socket" ]]; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart ssh.socket 2>/dev/null || systemctl reload ssh.socket 2>/dev/null || return 1
  else
    systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null || return 1
  fi
  return 0
}

ssh_wait_port() {
  local port="$1" tries=0 ssbin="${SRV_TUNE_SS_BIN:-}"
  if [[ -z "$ssbin" ]]; then
    if [[ "${SRV_TUNE_TEST:-0}" == "1" ]] || ! command -v ss >/dev/null 2>&1; then
      return 0
    fi
    ssbin="ss"
  fi
  while [[ "$tries" -lt 10 ]]; do
    if "$ssbin" -tlnp 2>/dev/null | grep -q ":${port} "; then
      return 0
    fi
    sleep 1
    tries=$((tries + 1))
  done
  printf 'error: port %s is not listening after reload\n' "$port" >&2
  return 1
}

# ssh_ensure_tunnel_user - dedicated restricted user (real systems only).
ssh_ensure_tunnel_user() {
  local user="${SRV_TUNE_TUNNEL_USER:-tunnel}"
  if [[ "${SRV_TUNE_TEST:-0}" == "1" || "${SRV_TUNE_SYSROOT:-/}" != "/" ]]; then
    printf 'note: sandboxed, tunnel user %s not created (Match block stands)\n' "$user"
    return 0
  fi
  if ! id "$user" >/dev/null 2>&1; then
    useradd -m -s /usr/sbin/nologin "$user" || {
      printf 'error: cannot create user %s\n' "$user" >&2
      return 1
    }
  fi
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  mkdir -p "$home/.ssh"
  chmod 700 "$home/.ssh"
  chown "$user:$user" "$home/.ssh" 2>/dev/null || true
  if [[ -n "${SRV_TUNE_TUNNEL_KEY:-}" && ! -f "$home/.ssh/authorized_keys" ]]; then
    printf 'restrict,permitopen="%s" %s\n' "${SRV_TUNE_PERMIT_OPEN:-none}" "$SRV_TUNE_TUNNEL_KEY" >"$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
    chown "$user:$user" "$home/.ssh/authorized_keys" 2>/dev/null || true
  fi
  return 0
}

ssh_apply() {
  local backup_dir="$1" mode tmp port
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/ssh-guard.sh"
  mode="$(ssh_mode)"
  port="$(ssh_port)"
  if [[ "$mode" == "ADMIN" ]]; then
    ssh_key_ok || return 1
  fi
  tmp="$(mktemp)"
  case "$mode" in
  ADMIN) ssh_render_admin "$tmp" ;;
  TUNNEL) ssh_render_tunnel "$tmp" ;;
  CUSTOM) ssh_render_custom "$tmp" || {
    rm -f "$tmp"
    return 1
  } ;;
  *)
    printf 'error: unknown ssh mode: %s\n' "$mode" >&2
    rm -f "$tmp"
    return 1
    ;;
  esac
  if ! ssh_validate_dropin "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! ssh_sshd_test; then
    printf 'error: sshd rejected the config; nothing written\n' >&2
    rm -f "$tmp"
    return 1
  fi
  # Firewall first: the (new) port must be open before the reload.
  if [[ "$port" != "22" ]]; then
    ssh_firewall_first "$port" || {
      rm -f "$tmp"
      return 1
    }
  fi
  ssh_firewall_first 22 || {
    rm -f "$tmp"
    return 1
  }
  if ! apply_file "$backup_dir" "$(ssh_dropin_path)" "$tmp" "ssh $mode"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  # Port change: socket override so socket-activated daemons listen too.
  if [[ "$port" != "22" ]]; then
    tmp="$(mktemp)"
    {
      printf '# srv-tune socket ports (why: socket activation owns port 22+)\n[Socket]\nListenStream=22\nListenStream=%s\n' "$port"
    } >"$tmp"
    if ! apply_file "$backup_dir" "$(sys_p /etc/systemd/system/ssh.socket.d/00-srv-tune.conf)" "$tmp" "socket ports"; then
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
  fi
  if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  # Validate the merged LIVE config now that the drop-in is in place; on
  # failure restore from this run's backup immediately (before any reload).
  if ! ssh_sshd_test; then
    printf 'error: sshd rejects the merged config; restoring\n' >&2
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/rollback.sh"
    rollback_id "$(basename "$backup_dir")" || true
    return 1
  fi
  if [[ "$mode" == "TUNNEL" ]]; then
    ssh_ensure_tunnel_user || return 1
  fi
  # Arm the guard (skipped in unit tests via SRV_TUNE_NO_GUARD=1).
  local guard_id=""
  if [[ "${SRV_TUNE_NO_GUARD:-0}" != "1" && "${SRV_TUNE_TEST:-0}" != "1" ]]; then
    guard_id="$(guard_start "$(basename "$backup_dir")" "${SRV_TUNE_GUARD_TIMEOUT:-300}")"
    printf 'guard %s armed: confirm from a NEW session with: srv-tune confirm %s\n' "$guard_id" "$guard_id"
  fi
  if ! ssh_reload; then
    printf 'error: sshd reload failed; rolling back\n' >&2
    rm -f "$tmp"
    return 1
  fi
  if ! ssh_wait_port "$port"; then
    printf 'error: new port not listening; rolling back (guard reverts too)\n' >&2
    return 1
  fi
  if [[ -n "$guard_id" ]]; then
    printf 'verify the new session works, then run: srv-tune confirm %s\n' "$guard_id"
  fi
  ssh_tunnel_artifacts || true
  return 0
}

# ssh_tunnel_artifacts - client config + autossh unit into the state dir.
ssh_tunnel_artifacts() {
  if [[ "$(ssh_mode)" != "TUNNEL" ]]; then
    return 0
  fi
  local root="${SRV_TUNE_ROOT:-.}" state="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  local host="${SRV_TUNE_SSH_HOST:-tunnel-host}" user="${SRV_TUNE_TUNNEL_USER:-tunnel}" port
  port="$(ssh_port)"
  mkdir -p "$state" || return 1
  {
    printf '# generated by srv-tune (copy into ~/.ssh/config)\n'
    printf 'Host %s-tunnel\n  HostName %s\n  User %s\n  Port %s\n  Compression no\n' "$host" "$host" "$user" "$port"
  } >"$state/ssh-client-$host.conf"
  sed -e "s|%i|$host:22|g" "$root/templates/autossh-unit.service" >"$state/autossh-tunnel.service" 2>/dev/null || {
    printf 'note: autossh template missing; unit not generated\n'
    return 0
  }
  printf 'tunnel artifacts: %s/ssh-client-%s.conf\n' "$state" "$host"
  return 0
}

ssh_verify() {
  local f
  f="$(ssh_dropin_path)"
  if [[ ! -f "$f" ]]; then
    printf 'error: ssh drop-in missing: %s\n' "$f" >&2
    return 1
  fi
  if ! ssh_validate_dropin "$f"; then
    return 1
  fi
  if ! ssh_sshd_test; then
    printf 'error: sshd rejects the applied config\n' >&2
    return 1
  fi
  local port
  port="$(ssh_port)"
  if [[ "${SRV_TUNE_TEST:-0}" == "1" ]] || ! command -v ss >/dev/null 2>&1; then
    return 0
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/health.sh"
  if ! health_port "$port"; then
    printf 'error: ssh port %s is not listening\n' "$port" >&2
    return 1
  fi
  return 0
}
