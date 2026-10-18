#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Post-module health checks. Exit codes: 0 = healthy, 1 = broken, 2 = skipped
# (tool missing; caller decides). Read-only unless stated.
# shellcheck shell=bash

if [[ -n "${__TEMPER_HEALTH_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_HEALTH_SOURCED=1

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

# --- optimizer.sh health: read-only drift check -----------------------------
# Replays the post-apply checks of every module recorded in
# applied-changes.log, plus state-dir sanity and pending guards. Writes
# nothing itself; module checks keep their own behavior (mirror verify runs
# apt-get update).
# Exit: 0 when no FAIL (WARN allowed), 1 on any FAIL.
# shortcut: replays run with THIS session's environment, not the apply-time
# env (fail2ban's ignoreip grep flags a new source IP). Upgrade to recorded
# per-apply env only if operators report noise.
__HEALTH_ROWS=()
__HEALTH_PASSES=0
__HEALTH_WARNS=0
__HEALTH_FAILS=0
__HEALTH_SKIPS=0

# health_emit <PASS|WARN|FAIL|SKIP|INFO> <name> <message>
health_emit() {
  local status="$1" name="$2" msg="$3"
  msg="$(printf '%s' "$msg" | tr '\n\t' '  ' | sed -e 's/  */ /g; s/^ //; s/ $//')"
  if [[ -z "$msg" ]]; then
    msg="-"
  fi
  __HEALTH_ROWS+=("$status|$name|$msg")
  case "$status" in
  PASS) __HEALTH_PASSES=$((__HEALTH_PASSES + 1)) ;;
  WARN) __HEALTH_WARNS=$((__HEALTH_WARNS + 1)) ;;
  FAIL) __HEALTH_FAILS=$((__HEALTH_FAILS + 1)) ;;
  SKIP) __HEALTH_SKIPS=$((__HEALTH_SKIPS + 1)) ;;
  esac
}

# health_guard_state <guard_id> - 0 armed (timer/sleeper alive), 1 resolved
# (fired or confirmed), 2 unknown (no probe tool here).
health_guard_state() {
  local id="$1" probed=0
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    probed=1
    if systemctl is-active --quiet "temper-guard-${id}.timer" 2>/dev/null; then
      return 0
    fi
  fi
  if command -v pgrep >/dev/null 2>&1; then
    probed=1
    if pgrep -f "cancelled-${id}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  if [[ "$probed" == "1" ]]; then
    return 1
  fi
  return 2
}

health_check_guards() {
  local base="$1" gdir f file id st unresolved=0
  gdir="$base/guard"
  if [[ -d "$gdir" ]]; then
    for f in "$gdir"/revert-*.sh; do
      if [[ ! -e "$f" ]]; then
        break
      fi
      file="${f##*/}"
      id="${file#revert-}"
      id="${id%.sh}"
      if [[ -e "$gdir/cancelled-$id" ]]; then
        continue
      fi
      unresolved=$((unresolved + 1))
      st=0
      health_guard_state "$id" || st=$?
      case "$st" in
      0) health_emit WARN "guard:$id" "still armed: timed auto-revert pending; confirm from a NEW session (temper confirm $id)" ;;
      1) health_emit WARN "guard:$id" "unconfirmed; auto-revert already fired (its changes were rolled back)" ;;
      *) health_emit WARN "guard:$id" "armed state unknown (no systemctl/pgrep here); check manually" ;;
      esac
    done
  fi
  if [[ "$unresolved" == "0" ]]; then
    health_emit PASS guards "no pending guards"
  fi
}

health_write_json() {
  local f="$1" tmp r st rest name msg lc overall first
  overall="pass"
  if [[ "$__HEALTH_FAILS" -gt 0 ]]; then
    overall="fail"
  fi
  tmp="$(mktemp)" || return 1
  {
    printf '{"status":"%s","checks":[' "$overall"
    first=1
    for r in "${__HEALTH_ROWS[@]}"; do
      st="${r%%|*}"
      rest="${r#*|}"
      name="${rest%%|*}"
      msg="${rest#*|}"
      lc="$(printf '%s' "$st" | tr 'A-Z' 'a-z')"
      if [[ "$first" != "1" ]]; then
        printf ','
      fi
      first=0
      printf '{"name":"%s","status":"%s","detail":"%s"}' "$(json_escape "$name")" "$lc" "$(json_escape "$msg")"
    done
    printf ']}\n'
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$f" || {
    rm -f "$tmp"
    return 1
  }
  printf 'health: json report written to %s\n' "$f"
}

# health_run - the doctor. Read-only; prints rows, returns 1 on any FAIL.
health_run() {
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/modules.sh"
  local base log m out rc can_check=0 seen=" " have=0 r st rest name msg
  base="${TEMPER_STATE_DIR:-/var/lib/temper}"

  if [[ ! -d "$base" ]]; then
    health_emit WARN state-dir "$base missing (nothing applied yet?)"
  elif path_is_world_writable "$base"; then
    health_emit FAIL state-dir "$base is world-writable (tampering risk)"
  elif [[ ! -w "$base" ]]; then
    health_emit WARN state-dir "$base not writable (apply would fail there)"
  else
    health_emit PASS state-dir "$base writable"
  fi

  health_check_guards "$base"

  log="$base/applied-changes.log"
  if [[ ! -f "$log" ]]; then
    health_emit INFO modules "no applied changes recorded; nothing to verify"
  else
    if is_root; then
      can_check=1
    fi
    if [[ "${TEMPER_SYSROOT:-/}" != "/" ]]; then
      can_check=1
    fi
    if [[ "$can_check" != "1" ]]; then
      health_emit WARN modules "not root and no sandbox: module checks skipped (run as root for full coverage)"
    else
      while IFS= read -r m; do
        if [[ "$seen" == *" $m "* ]]; then
          continue
        fi
        seen="$seen$m "
        have=1
        if ! module_load "$m"; then
          health_emit FAIL "module:$m" "module not present in this build"
          continue
        fi
        if out="$("${m}_verify" 2>&1)"; then
          rc=0
        else
          rc=$?
        fi
        case "$rc" in
        0) health_emit PASS "module:$m" "${out:-state verified}" ;;
        2) health_emit SKIP "module:$m" "${out:-nothing to check here}" ;;
        *) health_emit FAIL "module:$m" "${out:-verify failed}" ;;
        esac
      done < <(sed -n 's/.*module=\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$log" 2>/dev/null)
      if [[ "$have" == "0" ]]; then
        health_emit INFO modules "applied log has no module entries"
      fi
    fi
  fi

  if [[ -n "${TEMPER_JSON_OUT:-}" ]]; then
    health_write_json "$TEMPER_JSON_OUT" || health_emit WARN json "could not write $TEMPER_JSON_OUT"
  fi

  for r in "${__HEALTH_ROWS[@]}"; do
    st="${r%%|*}"
    rest="${r#*|}"
    name="${rest%%|*}"
    msg="${rest#*|}"
    printf '%-4s %-16s %s\n' "$st" "$name" "$msg"
  done
  printf 'health: %s pass, %s warn, %s fail, %s skip\n' \
    "$__HEALTH_PASSES" "$__HEALTH_WARNS" "$__HEALTH_FAILS" "$__HEALTH_SKIPS"

  if [[ "$__HEALTH_FAILS" -gt 0 ]]; then
    return 1
  fi
  return 0
}
