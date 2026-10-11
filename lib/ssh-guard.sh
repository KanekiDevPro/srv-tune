#!/usr/bin/env bash
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
  rm -f "$gdir/cancelled-${backup_id}"

  # Independent timer: systemd-run transient if available, else nohup fallback
  # (disowned: survives crash/disconnect of this session).
  if guard_use_systemd; then
    if systemd-run --quiet --on-active="${timeout}" --unit "srv-tune-guard-${backup_id}" --timer-property=AccuracySec=5 \
      "$revert_script" >/dev/null 2>&1; then
      printf '%s\n' "$backup_id"
      return 0
    fi
  fi
  # shellcheck disable=SC2086
  nohup bash -c "sleep ${timeout}; test -f '$gdir/cancelled-${backup_id}' || bash '$revert_script'" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  printf '%s\n' "$backup_id"
}

# guard_confirm <backup_id> — must run from a NEW session (different tty).
guard_confirm() {
  local backup_id="$1"
  local force="${2:-0}"
  local gdir origin current
  gdir="$(guard_dir)"
  origin="$(cat "$gdir/origin-${backup_id}.tty" 2>/dev/null || printf 'unknown')"
  current="$(_current_tty)"
  if [[ "$origin" == "unknown" ]]; then
    printf 'warn: origin session unknown; cannot prove a NEW session\n' >&2
  fi
  if [[ "$force" != "1" && "$origin" != "unknown" && "$origin" == "$current" ]]; then
    printf 'error: confirm must run from a NEW session (origin=%s current=%s). Use --force to override.\n' "$origin" "$current" >&2
    return 1
  fi
  touch "$gdir/cancelled-${backup_id}"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "srv-tune-guard-${backup_id}.timer" >/dev/null 2>&1 || true
  fi
  printf 'guard %s confirmed and cancelled\n' "$backup_id"
}
