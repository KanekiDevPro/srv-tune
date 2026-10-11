#!/usr/bin/env bash
# SSH guard: independent timed auto-revert that survives crash/disconnect.
# Confirm only via `optimizer confirm` from a NEW session.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_SSHGUARD_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_SSHGUARD_SOURCED=1

guard_dir() {
  printf '%s/guard\n' "${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
}

_current_tty() {
  tty 2>/dev/null || printf '%s' "${SSH_TTY:-${SSH_CONNECTION:-unknown}}"
}

# guard_start <backup_id> <timeout_secs> — schedules independent revert.
guard_start() {
  local backup_id="$1"
  local timeout="${2:-300}"
  local gdir revert_script
  gdir="$(guard_dir)"
  mkdir -p "$gdir" || return 1
  revert_script="$gdir/revert-${backup_id}.sh"
  cat >"$revert_script" <<EOF
#!/usr/bin/env bash
# Auto-revert for guard $backup_id. Cancelled by 'optimizer confirm'.
set -u
STATE_DIR="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}"
if [[ -f "\$STATE_DIR/guard/cancelled-${backup_id}" ]]; then
  exit 0
fi
if [[ -f "\$STATE_DIR/backups/${backup_id}/manifest.tsv" ]]; then
  SRV_TUNE_STATE_DIR="\$STATE_DIR" bash "$(dirname "${BASH_SOURCE[0]:-.}")/../lib/rollback.sh" 2>/dev/null || true
fi
EOF
  chmod +x "$revert_script" 2>/dev/null || true
  printf '%s\n' "$(_current_tty)" >"$gdir/origin-${backup_id}.tty"
  rm -f "$gdir/cancelled-${backup_id}"

  # Independent timer: systemd-run transient if available, else nohup fallback.
  if command -v systemd-run >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemd-run --quiet --on-active="${timeout}" --unit "srv-tune-guard-${backup_id}" --timer-property=AccuracySec=5 \
      "$revert_script" >/dev/null 2>&1 || true
  else
    # shellcheck disable=SC2086
    nohup bash -c "sleep ${timeout}; test -f '$gdir/cancelled-${backup_id}' || bash '$revert_script'" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
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
