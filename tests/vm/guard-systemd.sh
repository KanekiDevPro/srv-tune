#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ssh-guard integration with REAL systemd-run (GitHub runners boot systemd).
# Temp files only: never touches the runner's sshd/network config.
# Run as root: sudo bash tests/vm/guard-systemd.sh
# shellcheck shell=bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" != "0" ]]; then
  printf 'error: run as root (sudo bash %s)\n' "$0" >&2
  exit 2
fi
if ! command -v systemd-run >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
  printf 'error: no system systemd here (needs PID 1 systemd)\n' >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SRV_TUNE_STATE_DIR
SRV_TUNE_STATE_DIR="$(mktemp -d /tmp/srv-guard-int-XXXXXX)"
export SRV_TUNE_TEST=1
# Real backend (not the nohup fallback, not stubs).
unset SRV_TUNE_GUARD_BACKEND

cleanup() {
  systemctl stop 'srv-tune-guard-g1.timer' >/dev/null 2>&1 || true
  systemctl stop 'srv-tune-guard-g2.timer' >/dev/null 2>&1 || true
  systemctl stop 'srv-tune-guard-g3.timer' >/dev/null 2>&1 || true
  rm -rf "${SRV_TUNE_STATE_DIR:-/nonexistent-srv-tune-state}" 2>/dev/null || true
}
trap cleanup EXIT

# shellcheck disable=SC1091
source "$ROOT/lib/ssh-guard.sh"

mkcase() {
  # mkcase <id> : broken canary + manifest with the original.
  local id="$1"
  local target="$SRV_TUNE_STATE_DIR/$id-canary.conf"
  local snap="$SRV_TUNE_STATE_DIR/backups/$id"
  mkdir -p "$snap"
  printf 'original\n' >"$target"
  cp "$target" "$snap/canary.conf"
  printf 'ts\t%s\t%s\n' "$target" "$snap/canary.conf" >"$snap/manifest.tsv"
  printf 'broken\n' >"$target"
  printf '%s\n' "$target"
}

wait_for() {
  # wait_for <timeout_s> <cmd...> : condition polling, no blind sleeps.
  local timeout="$1"
  shift
  local _try
  for _try in $(seq 1 "$((timeout * 2))"); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

printf '=== 1. schedule revert, kill -9 the parent, revert must fire ===\n'
t1="$(mkcase g1)"
SSH_TTY=/dev/pts/90 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_start g1 12 >/dev/null; sleep 20" &
parent=$!
wait_for 10 test -f "$SRV_TUNE_STATE_DIR/guard/origin-g1.tty"
timer_scheduled() {
  systemctl list-timers 'srv-tune-guard-g1.timer' 2>/dev/null | grep -q 'srv-tune-guard-g1'
}
# guard_start writes origin-g1.tty before systemd-run returns; poll so this
# probe cannot outrun scheduling on a loaded runner (flake seen in CI).
wait_for 10 timer_scheduled || {
  printf 'FAIL: transient timer not scheduled\n' >&2
  printf '--- systemd-run error (if any) ---\n' >&2
  cat "$SRV_TUNE_STATE_DIR/guard/systemd-run.err" >&2 || true
  printf '--- timer status ---\n' >&2
  systemctl status 'srv-tune-guard-g1.timer' >&2 || true
  systemctl --version | head -n 1 >&2 || true
  exit 1
}
kill -9 "$parent"
wait "$parent" 2>/dev/null || true
canary_is_original() {
  [[ "$(cat "$t1")" == "original" ]]
}
printf 'parent dead; waiting for the independent timer to fire...\n'
wait_for 30 canary_is_original || {
  printf 'FAIL: canary=%s (expected original)\n' "$(cat "$t1")" >&2
  exit 1
}
printf 'PASS: revert fired with no parent alive\n'

printf '=== 2. NEW-session confirm cancels ===\n'
t2="$(mkcase g2)"
SSH_TTY=/dev/pts/90 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_start g2 8 >/dev/null"
SSH_TTY=/dev/pts/91 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_confirm g2"
test -f "$SRV_TUNE_STATE_DIR/guard/cancelled-g2"
if systemctl list-timers 'srv-tune-guard-g2.timer' 2>/dev/null | grep -q 'srv-tune-guard-g2'; then
  printf 'FAIL: timer still active after confirm\n' >&2
  exit 1
fi
# Functional proof: past the 8s timeout the canary is still broken (no revert).
sleep 12
if [[ "$(cat "$t2")" != "broken" ]]; then
  printf 'FAIL: canary reverted despite confirm: %s\n' "$(cat "$t2")" >&2
  exit 1
fi
printf 'PASS: new-session confirm cancelled the timer\n'

printf '=== 3. SAME-session confirm is rejected ===\n'
mkcase g3 >/dev/null
SSH_TTY=/dev/pts/90 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_start g3 30 >/dev/null"
if SSH_TTY=/dev/pts/90 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_confirm g3" 2>/dev/null; then
  printf 'FAIL: same-session confirm accepted\n' >&2
  exit 1
fi
test ! -f "$SRV_TUNE_STATE_DIR/guard/cancelled-g3"
SSH_TTY=/dev/pts/90 bash -c "source '$ROOT/lib/ssh-guard.sh'; export SRV_TUNE_STATE_DIR='$SRV_TUNE_STATE_DIR'; guard_confirm g3 1 >/dev/null"
printf 'PASS: same-session confirm rejected (force works for cleanup)\n'

printf 'ALL GUARD-SYSTEMD CHECKS PASSED\n'
