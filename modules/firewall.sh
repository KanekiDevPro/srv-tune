#!/usr/bin/env bash
# firewall: ufw or nftables (iptables = hands-off note). Never enables anything
# without the current SSH port allowed first; default-deny only under guard.
# nftables validates with nft -c and applies atomically with nft -f.
# Contract: firewall_detect|allow_port|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

firewall_tool() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'active'; then
    printf 'ufw\n'
  elif command -v ufw >/dev/null 2>&1; then
    printf 'ufw-inactive\n'
  elif command -v nft >/dev/null 2>&1; then
    printf 'nftables\n'
  elif command -v iptables >/dev/null 2>&1; then
    printf 'iptables\n'
  else
    printf 'none\n'
  fi
}

firewall_ssh_port() {
  printf '%s\n' "${SRV_TUNE_SSH_PORT:-22}"
}

firewall_session_src() {
  local c="${SSH_CONNECTION:-}"
  if [[ -n "$c" ]]; then
    printf '%s\n' "${c%% *}"
  else
    printf 'unknown\n'
  fi
}

firewall_is_live() {
  [[ "${SRV_TUNE_TEST:-0}" != "1" && "${SRV_TUNE_SYSROOT:-/}" == "/" ]]
}

firewall_detect() {
  printf 'TOOL=%s\nSSH_PORT=%s\nSESSION_SRC=%s\n' "$(firewall_tool)" "$(firewall_ssh_port)" "$(firewall_session_src)"
}

firewall_recommend() {
  local tool src
  tool="$(firewall_tool)"
  src="$(firewall_session_src)"
  printf 'tool: %s (why: detected, never replaced)\n' "$tool"
  printf 'allow TCP/%s BEFORE enabling anything (why: keep this session alive)\n' "$(firewall_ssh_port)"
  if [[ "$src" != "unknown" ]]; then
    printf 'session source %s stays reachable (why: anti-lockout)\n' "$src"
  fi
  printf 'default-deny only under guard + NEW-session confirm (why: revert on silence)\n'
}

# firewall_allow_port <port> - immediate allow (ufw) or pending list (nft).
firewall_allow_port() {
  local port="$1" tool state
  tool="$(firewall_tool)"
  state="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  case "$tool" in
  ufw | ufw-inactive)
    if ! firewall_is_live; then
      mkdir -p "$state"
      printf 'allow %s\n' "$port" >>"$state/fw-intent.log"
      printf 'note: sandboxed, ufw allow %s recorded (not executed)\n' "$port"
      return 0
    fi
    if ufw status numbered 2>/dev/null | grep -q "$port/tcp.*ALLOW"; then
      printf 'ufw already allows %s/tcp\n' "$port"
      return 0
    fi
    ufw allow "$port/tcp" || {
      printf 'error: ufw allow %s failed\n' "$port" >&2
      return 1
    }
    ;;
  nftables)
    mkdir -p "$state"
    if ! grep -qx "$port" "$state/fw-pending-ports.log" 2>/dev/null; then
      printf '%s\n' "$port" >>"$state/fw-pending-ports.log"
    fi
    if firewall_is_live; then
      firewall_ensure_nft || return 1
    else
      printf 'note: sandboxed, nft port %s pending (not applied)\n' "$port"
    fi
    ;;
  *)
    printf 'note: firewall tool is %s; open TCP/%s manually before reload\n' "$tool" "$port"
    ;;
  esac
  return 0
}

# firewall_nft_ports - pending ports plus ssh port, one per line, deduped.
firewall_nft_ports() {
  local state ports p
  state="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  ports="$(firewall_ssh_port)"
  if [[ -f "$state/fw-pending-ports.log" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      ports="$ports $p"
    done <"$state/fw-pending-ports.log"
  fi
  printf '%s\n' "$ports" | tr ' ' '\n' | sort -un | tr '\n' ' '
}

# firewall_render_nft <out> - full table; REFUSES if the ssh port is absent.
firewall_render_nft() {
  local out="$1" ports dports p
  ports="$(firewall_nft_ports)"
  dports=""
  for p in $ports; do
    # shellcheck disable=SC2086
    if [[ ! "$p" =~ ^[0-9]+$ ]]; then
      printf 'error: bad port in nft set: %s\n' "$p" >&2
      return 1
    fi
    dports="$dports$p, "
  done
  dports="{ ${dports%, } }"
  # Anti-lockout assertion: the ssh port MUST be in the accept set.
  case " $ports " in
  *' '"$(firewall_ssh_port)"' '*) ;;
  *)
    printf 'error: ssh port %s missing from nft accept set; refusing (would cut this session)\n' "$(firewall_ssh_port)" >&2
    return 1
    ;;
  esac
  {
    printf '# srv-tune nftables (why: atomic file, validated with nft -c)\n'
    printf 'table inet srv_tune {\n'
    printf '  chain input {\n'
    printf '    type filter hook input priority 0; policy drop;\n'
    printf '    ct state established,related accept\n'
    printf '    iif "lo" accept\n'
    printf '    tcp dport %s accept\n' "$dports"
    printf '  }\n}\n'
  } >"$out"
  return 0
}

# firewall_ensure_nft - validate with nft -c, apply atomically with nft -f.
firewall_ensure_nft() {
  local tmp="$1"
  local own_tmp=0
  if [[ -z "$tmp" ]]; then
    tmp="$(mktemp)"
    own_tmp=1
  fi
  firewall_render_nft "$tmp" || {
    [[ "$own_tmp" == "1" ]] && rm -f "$tmp"
    return 1
  }
  if ! nft -c -f "$tmp" 2>/dev/null; then
    printf 'error: nft -c rejected the ruleset; nothing applied\n' >&2
    [[ "$own_tmp" == "1" ]] && rm -f "$tmp"
    return 1
  fi
  nft -f "$tmp" || {
    printf 'error: nft -f failed\n' >&2
    [[ "$own_tmp" == "1" ]] && rm -f "$tmp"
    return 1
  }
  if [[ "$own_tmp" == "1" ]]; then
    rm -f "$tmp"
  fi
  return 0
}

firewall_apply() {
  local backup_dir="$1" tool
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/ssh-guard.sh"
  tool="$(firewall_tool)"
  case "$tool" in
  ufw | ufw-inactive)
    if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
      printf 'dry-run: ufw allow %s/tcp then enable (why: port first)\n' "$(firewall_ssh_port)"
      return 0
    fi
    firewall_allow_port "$(firewall_ssh_port)" || return 1
    if [[ "$(firewall_ssh_port)" != "22" ]]; then
      firewall_allow_port 22 || return 1
    fi
    if ! firewall_is_live; then
      printf 'enable\n' >>"${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}/fw-intent.log"
      printf 'note: sandboxed, ufw enable skipped\n'
      return 0
    fi
    local guard_id
    guard_id="$(guard_start "$(basename "$backup_dir")" "${SRV_TUNE_GUARD_TIMEOUT:-300}")"
    printf 'guard %s armed: confirm with srv-tune confirm %s\n' "$guard_id" "$guard_id"
    if ! ufw --force enable 2>/dev/null; then
      printf 'error: ufw enable failed\n' >&2
      return 1
    fi
    printf 'verify with a NEW session, then run: srv-tune confirm %s\n' "$guard_id"
    ;;
  nftables)
    local tmp
    tmp="$(mktemp)"
    if ! firewall_render_nft "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    if ! apply_file "$backup_dir" "$(sys_p /etc/nftables.d/00-srv-tune.nft)" "$tmp" "nftables base set"; then
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
    if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
      return 0
    fi
    if ! firewall_is_live; then
      printf 'note: sandboxed, nft -f skipped; persist by loading this file at boot (see recommend)\n'
      return 0
    fi
    local guard_id
    guard_id="$(guard_start "$(basename "$backup_dir")" "${SRV_TUNE_GUARD_TIMEOUT:-300}")"
    printf 'guard %s armed: confirm with srv-tune confirm %s\n' "$guard_id" "$guard_id"
    firewall_ensure_nft "$(sys_p /etc/nftables.d/00-srv-tune.nft)" || return 1
    printf 'note: load this file at boot (nft -f in local process); verify, then: srv-tune confirm %s\n' "$guard_id"
    ;;
  *)
    printf 'skip: firewall tool is %s (ufw/nftables only; iptables managed manually)\n' "$tool"
    return 2
    ;;
  esac
  return 0
}

firewall_verify() {
  local tool
  tool="$(firewall_tool)"
  case "$tool" in
  ufw)
    if ! firewall_is_live; then
      return 0
    fi
    ufw status 2>/dev/null | grep -q "$(firewall_ssh_port)/tcp.*ALLOW" || {
      printf 'error: ufw does not allow %s/tcp\n' "$(firewall_ssh_port)" >&2
      return 1
    }
    ;;
  nftables)
    if ! firewall_is_live; then
      [[ -f "$(sys_p /etc/nftables.d/00-srv-tune.nft)" ]] || {
        printf 'error: nft drop-in missing\n' >&2
        return 1
      }
      return 0
    fi
    nft list ruleset 2>/dev/null | grep -q 'srv_tune' || {
      printf 'error: srv_tune table not loaded\n' >&2
      return 1
    }
    ;;
  *)
    return 0
    ;;
  esac
  return 0
}
