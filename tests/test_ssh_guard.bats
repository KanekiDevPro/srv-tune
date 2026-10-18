#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# ssh-guard: independent timer, NEW-session confirm rule, real auto-revert.
# systemd is stubbed (PATH); the nohup path runs for real with timeout=1.
# shellcheck shell=bash

load bats_helper

_make_stubs() {
  local d="$TEMPER_TMP/stubbin"
  mkdir -p "$d"
  cat >"$d/systemd-run" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEMPER_TMP/systemd-run.log"
exit 0
EOF
  cat >"$d/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEMPER_TMP/systemctl.log"
exit 0
EOF
  chmod +x "$d/systemd-run" "$d/systemctl"
  # Deterministic clocks: fake date/ps controlled by env, real ones baked in.
  local realdate realps
  realdate="$(command -v date)"
  realps="$(command -v ps || printf '')"
  cat >"$d/date" <<EOF
#!/usr/bin/env bash
if [[ -n "\${TEMPER_STUB_DATE:-}" ]]; then printf '%s\n' "\$TEMPER_STUB_DATE"; else exec "$realdate" "\$@"; fi
EOF
  cat >"$d/ps" <<EOF
#!/usr/bin/env bash
if [[ "\${TEMPER_STUB_ETIMES:-}" == "fail" ]]; then exit 1; fi
if [[ -n "\${TEMPER_STUB_ETIMES:-}" ]]; then printf '%s\n' "\$TEMPER_STUB_ETIMES"; else exec "$realps" "\$@"; fi
EOF
  chmod +x "$d/date" "$d/ps"
  printf '%s\n' "$d"
}

@test "guard_start records origin and schedules a systemd timer" {
  local stubs
  stubs="$(_make_stubs)"
  run env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "myid" ]]
  [ "$(cat "$TEMPER_STATE_DIR/guard/origin-myid.tty")" = "/dev/pts/7" ]
  [ -x "$TEMPER_STATE_DIR/guard/revert-myid.sh" ]
  grep -q -- "--on-active=300" "$TEMPER_TMP/systemd-run.log"
  grep -q "revert-myid.sh" "$TEMPER_TMP/systemd-run.log"
}

@test "guard_confirm from the SAME session is rejected" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_confirm myid' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEW session"* ]]
  [ ! -f "$TEMPER_STATE_DIR/guard/cancelled-myid" ]
}

@test "guard_confirm from a NEW session cancels (and stops the timer)" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 TEMPER_STUB_DATE=1000 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/9 TEMPER_STUB_DATE=1100 TEMPER_STUB_ETIMES=5 \
    bash -c 'source "$1"; guard_confirm myid' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"confirmed and cancelled"* ]]
  [ -f "$TEMPER_STATE_DIR/guard/cancelled-myid" ]
  grep -q "stop temper-guard-myid.timer" "$TEMPER_TMP/systemctl.log"
}

@test "guard_confirm rejects an older session even with a different tty" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 TEMPER_STUB_DATE=1000 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  # Different tty (passes the tty rule) but started before the apply.
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/9 TEMPER_STUB_DATE=1000 TEMPER_STUB_ETIMES=50 \
    bash -c 'source "$1"; guard_confirm myid' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEWER sessions"* ]]
  [ ! -f "$TEMPER_STATE_DIR/guard/cancelled-myid" ]
}

@test "guard_confirm warns and keeps the tty rule when age is undeterminable" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 TEMPER_STUB_DATE=1000 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/9 TEMPER_STUB_DATE=1100 TEMPER_STUB_ETIMES=fail \
    bash -c 'source "$1"; guard_confirm myid' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tty rule only"* ]]
  [ -f "$TEMPER_STATE_DIR/guard/cancelled-myid" ]
}

@test "guard_confirm --force overrides the same-session rule" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" TEMPER_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_confirm myid 1' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_STATE_DIR/guard/cancelled-myid" ]
}

@test "nohup fallback reverts after timeout when not confirmed (parent exits)" {
  local target="$TEMPER_TMP/protected.conf"
  printf 'original\n' >"$target"
  local snap="$TEMPER_STATE_DIR/backups/g1"
  mkdir -p "$snap"
  cp "$target" "$snap/protected.conf"
  printf 'ts\t%s\t%s\n' "$target" "$snap/protected.conf" >"$snap/manifest.tsv"
  # Break the file, arm the guard with timeout=1, then let THIS process
  # (the "session") go away: the revert must still fire.
  printf 'broken\n' >"$target"
  run env TEMPER_GUARD_BACKEND=nohup SSH_TTY=/dev/pts/3 \
    bash -c 'source "$1"; guard_start g1 1' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  local _try
  for _try in $(seq 1 100); do
    [[ "$(cat "$target")" == "original" ]] && break
    sleep 0.1
  done
  [ "$(cat "$target")" = "original" ]
}

@test "nohup fallback does NOT revert after confirm" {
  local target="$TEMPER_TMP/keep.conf"
  printf 'original\n' >"$target"
  local snap="$TEMPER_STATE_DIR/backups/g2"
  mkdir -p "$snap"
  cp "$target" "$snap/keep.conf"
  printf 'ts\t%s\t%s\n' "$target" "$snap/keep.conf" >"$snap/manifest.tsv"
  printf 'broken\n' >"$target"
  env TEMPER_GUARD_BACKEND=nohup SSH_TTY=/dev/pts/3 \
    bash -c 'source "$1"; guard_start g2 1 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  env SSH_TTY=/dev/pts/4 bash -c 'source "$1"; guard_confirm g2 >/dev/null' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  sleep 2
  [ "$(cat "$target")" = "broken" ]
}

@test "guard survives parent kill -9 (independence from the session)" {
  local stubs
  stubs="$(_make_stubs)"
  local session="$TEMPER_TMP/session.sh" ready="$TEMPER_TMP/k9.ready"
  cat >"$session" <<EOF
source "$TEMPER_ROOT/lib/ssh-guard.sh"
export TEMPER_STATE_DIR="$TEMPER_STATE_DIR"
export SSH_TTY=/dev/pts/5
export PATH="$stubs:$PATH"
export TEMPER_GUARD_BACKEND=systemd
guard_start k9 300 >/dev/null
printf 'ready\n' >"$ready"
sleep 30
EOF
  bash "$session" &
  local pid=$!
  local _try ready_ok
  ready_ok=0
  for _try in $(seq 1 100); do
    if [[ -f "$ready" ]]; then
      ready_ok=1
      break
    fi
    sleep 0.1
  done
  if [[ "$ready_ok" != "1" ]]; then
    kill -9 "$pid" 2>/dev/null || true
    printf 'session never finished arming the guard\n' >&2
    return 1
  fi
  # The whole session dies violently; the scheduled timer must already exist.
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ -f "$TEMPER_STATE_DIR/guard/origin-k9.tty" ]
  [ -x "$TEMPER_STATE_DIR/guard/revert-k9.sh" ]
  grep -q -- "--on-active=300" "$TEMPER_TMP/systemd-run.log"
}
