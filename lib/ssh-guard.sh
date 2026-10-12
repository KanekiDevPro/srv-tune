#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SSH guard: independent timed auto-revert that survives crash/disconnect.
# Confirm only via `optimizer confirm` from a NEW session.
# SRV_TUNE_GUARD_BACKEND: auto (default) | systemd | nohup. Tests override it;
# production leaves it unset.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_SSHGUARD_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_SSHGUARD_SOURCED=1

guard_dir() {
  printf '%s/guard\n' "${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
}

_current_tty() {
  # tty prints "not a tty" to STDOUT on failure: capture then validate.
  local t
  t="$(tty 2>/dev/null)" || t=""
  case "$t" in
  /dev/*)
    printf '%s\n' "$t"
    return 0
    ;;
  esac
  printf '%s\n' "${SSH_TTY:-${SSH_CONNECTION:-unknown}}"
}

guard_use_systemd() {
  if [[ "${SRV_TUNE_GUARD_BACKEND:-auto}" == "nohup" ]]; then
    return 1
  fi
  if [[ "${SRV_TUNE_GUARD_BACKEND:-auto}" == "systemd" ]]; then
    return 0
  fi
  command -v systemd-run >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

# guard_start <backup_id> <timeout_secs> — schedules independent revert.
guard_start() {
  local backup_id="$1"
  local timeout="${2:-300}"
  # Numeric guard: timeout lands unquoted in a nohup command line.
  case "$timeout" in
  '' | *[!0-9]*) timeout=300 ;;
  esac
  local gdir revert_script state_dir
  gdir="$(guard_dir)"
  state_dir="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
  mkdir -p "$gdir" || return 1
  revert_script="$gdir/revert-${backup_id}.sh"
  # Self-contained: embeds the restore loop so firing needs no install paths.
  cat >"$revert_script" <<EOF
#!/usr/bin/env bash
# Auto-revert for guard $backup_id. Cancelled by 'optimizer confirm'.
set -u
STATE_DIR="$state_dir"
if [[ -f "\$STATE_DIR/guard/cancelled-$backup_id" ]]; then
  exit 0
fi
MANIFEST="\$STATE_DIR/backups/$backup_id/manifest.tsv"
[[ -f "\$MANIFEST" ]] || exit 0
while IFS="$(printf '\t')" read -r _ts src bak; do
  [[ -z "\$src" ]] && continue
  if [[ "\$bak" == "(absent)" ]]; then
    rm -f "\$src"
  elif [[ -f "\$bak" ]]; then
    mkdir -p "\$(dirname "\$src")"
    cp -a "\$bak" "\$src" 2>/dev/null || cp "\$bak" "\$src" || true
  fi
done <"\$MANIFEST"
EOF
  chmod +x "$revert_script" 2>/dev/null || true
  printf '%s\n' "$(_current_tty)" >"$gdir/origin-${backup_id}.tty"
  date +%s >"$gdir/apply-${backup_id}.ts" 2>/dev/null || printf '0\n' >"$gdir/apply-${backup_id}.ts"
  rm -f "$gdir/cancelled-${backup_id}"

  # Independent timer: systemd-run transient if available, else nohup fallback
  # (disowned: survives crash/disconnect of this session).
  if guard_use_systemd; then
    local run_err
    if run_err="$(systemd-run --quiet --on-active="${timeout}" --unit "srv-tune-guard-${backup_id}" --timer-property=AccuracySec=5 \
      "$revert_script" 2>&1 >/dev/null)"; then
      printf '%s\n' "$backup_id"
      return 0
    fi
    # Visible for post-mortem (integration job dumps this on failure).
    printf '%s\n' "$run_err" >"$gdir/systemd-run.err"
  fi
  # shellcheck disable=SC2086
  nohup bash -c "sleep ${timeout}; test -f '$gdir/cancelled-${backup_id}' || bash '$revert_script'" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  printf '%s\n' "$backup_id"
}

# session_start_epoch - when the CALLER's session began (epoch secs).
# ps etimes first, then tty device mtime. Fails when neither works.
session_start_epoch() {
  local now et
  now="$(date +%s 2>/dev/null || printf '0')"
  et="$(ps -o etimes= -p $$ 2>/dev/null | tr -d ' ' || true)"
  if [[ "$et" =~ ^[0-9]+$ ]] && [[ "$now" != "0" ]]; then
    printf '%s\n' "$((now - et))"
    return 0
  fi
  local t mtime
  t="$(tty 2>/dev/null || true)"
  case "$t" in
  /dev/*)
    mtime="$(stat -c %Y "$t" 2>/dev/null || stat -f %B "$t" 2>/dev/null || true)"
    if [[ "$mtime" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$mtime"
      return 0
    fi
    ;;
  esac
  return 1
}

# guard_confirm <backup_id> — must run from a NEW session: different tty AND
# login time AFTER the apply timestamp. Older/same sessions are rejected
# (steals of an old terminal cannot confirm). --force overrides with a warning.
guard_confirm() {
  local backup_id="$1"
  local force="${2:-0}"
  local gdir origin current apply_ts start
  gdir="$(guard_dir)"
  origin="$(cat "$gdir/origin-${backup_id}.tty" 2>/dev/null || printf 'unknown')"
  apply_ts="$(cat "$gdir/apply-${backup_id}.ts" 2>/dev/null || printf '')"
  current="$(_current_tty)"
  if [[ "$origin" == "unknown" ]]; then
    printf 'warn: origin session unknown; cannot prove a NEW session\n' >&2
  fi
  if [[ "$force" != "1" && "$origin" != "unknown" && "$origin" == "$current" ]]; then
    printf 'error: confirm must run from a NEW session (origin=%s current=%s). Use --force to override.\n' "$origin" "$current" >&2
    return 1
  fi
  if [[ -n "$apply_ts" && "$force" != "1" ]]; then
    # Enforced where measurable (ps/stat exist: every real server). Where the
    # session age is undeterminable (minimal shells), keep the tty-only rule
    # with a loud warning instead of bricking legitimate confirms.
    if ! start="$(session_start_epoch)"; then
      printf 'warn: cannot determine this session start; tty rule only\n' >&2
    elif [[ ! "$start" =~ ^[0-9]+$ ]] || [[ ! "$apply_ts" =~ ^[0-9]+$ ]]; then
      printf 'error: unreadable timestamps (start=%s apply=%s); refusing without --force\n' "$start" "$apply_ts" >&2
      return 1
    # Strictly-older only: date has 1s resolution, so same-second is
    # ambiguous, not provably older (fast legit confirms land here). The
    # tty rule above still rejects the identical session.
    elif [[ "$start" -lt "$apply_ts" ]]; then
      printf 'error: this session started at %s, apply was at %s: only NEWER sessions may confirm. Use --force to override.\n' "$start" "$apply_ts" >&2
      return 1
    fi
  fi
  # Deferred lockdowns (e.g. ADMIN password switch) complete here, only
  # after a NEW session proved access. A failed finalize keeps the guard
  # armed (no cancel) so the timer still reverts.
  local pending
  pending="$gdir/pending-${backup_id}.lockdown"
  if [[ -f "$pending" ]]; then
    local root="${SRV_TUNE_ROOT:-.}"
    if [[ -f "$root/modules/ssh.sh" ]]; then
      # shellcheck disable=SC1090
      source "$root/modules/ssh.sh"
      if ! ssh_finalize_passwordless "$backup_id"; then
        printf 'error: pending lockdown failed; guard stays armed\n' >&2
        return 1
      fi
    else
      printf 'warn: pending lockdown %s skipped (ssh module missing)\n' "$pending" >&2
      rm -f "$pending"
    fi
  fi
  touch "$gdir/cancelled-${backup_id}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "srv-tune-guard-${backup_id}.timer" >/dev/null 2>&1 || true
  fi
  printf 'guard %s confirmed and cancelled\n' "$backup_id"
}
