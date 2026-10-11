#!/usr/bin/env bats
# ssh-guard: independent timer, NEW-session confirm rule, real auto-revert.
# systemd is stubbed (PATH); the nohup path runs for real with timeout=1.
# shellcheck shell=bash

load bats_helper

_make_stubs() {
  local d="$SRV_TUNE_TMP/stubbin"
  mkdir -p "$d"
  cat >"$d/systemd-run" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$SRV_TUNE_TMP/systemd-run.log"
exit 0
EOF
  cat >"$d/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$SRV_TUNE_TMP/systemctl.log"
exit 0
EOF
  chmod +x "$d/systemd-run" "$d/systemctl"
  printf '%s\n' "$d"
}

@test "guard_start records origin and schedules a systemd timer" {
  local stubs
  stubs="$(_make_stubs)"
  run env PATH="$stubs:$PATH" SRV_TUNE_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "myid" ]]
  [ "$(cat "$SRV_TUNE_STATE_DIR/guard/origin-myid.tty")" = "/dev/pts/7" ]
  [ -x "$SRV_TUNE_STATE_DIR/guard/revert-myid.sh" ]
  grep -q -- "--on-active=300" "$SRV_TUNE_TMP/systemd-run.log"
  grep -q "revert-myid.sh" "$SRV_TUNE_TMP/systemd-run.log"
}

@test "guard_confirm from the SAME session is rejected" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" SRV_TUNE_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_confirm myid' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEW session"* ]]
  [ ! -f "$SRV_TUNE_STATE_DIR/guard/cancelled-myid" ]
}

@test "guard_confirm from a NEW session cancels (and stops the timer)" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" SRV_TUNE_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/9 \
    bash -c 'source "$1"; guard_confirm myid' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"confirmed and cancelled"* ]]
  [ -f "$SRV_TUNE_STATE_DIR/guard/cancelled-myid" ]
  grep -q "stop srv-tune-guard-myid.timer" "$SRV_TUNE_TMP/systemctl.log"
}

@test "guard_confirm --force overrides the same-session rule" {
  local stubs
  stubs="$(_make_stubs)"
  env PATH="$stubs:$PATH" SRV_TUNE_GUARD_BACKEND=systemd SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_start myid 300 >/dev/null' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  run env PATH="$stubs:$PATH" SSH_TTY=/dev/pts/7 \
    bash -c 'source "$1"; guard_confirm myid 1' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_STATE_DIR/guard/cancelled-myid" ]
}

@test "nohup fallback reverts after timeout when not confirmed (parent exits)" {
  local target="$SRV_TUNE_TMP/protected.conf"
  printf 'original\n' >"$target"
  local snap="$SRV_TUNE_STATE_DIR/backups/g1"
  mkdir -p "$snap"
  cp "$target" "$snap/protected.conf"
  printf 'ts\t%s\t%s\n' "$target" "$snap/protected.conf" >"$snap/manifest.tsv"
  # Break the file, arm the guard with timeout=1, then let THIS process
  # (the "session") go away: the revert must still fire.
  printf 'broken\n' >"$target"
  run env SRV_TUNE_GUARD_BACKEND=nohup SSH_TTY=/dev/pts/3 \
    bash -c 'source "$1"; guard_start g1 1' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  local _try
  for _try in $(seq 1 50); do
    [[ "$(cat "$target")" == "original" ]] && break
    sleep 0.1
  done
  [ "$(cat "$target")" = "original" ]
}

@test "nohup fallback does NOT revert after confirm" {
  local target="$SRV_TUNE_TMP/keep.conf"
  printf 'original\n' >"$target"
  local snap="$SRV_TUNE_STATE_DIR/backups/g2"
  mkdir -p "$snap"
  cp "$target" "$snap/keep.conf"
  printf 'ts\t%s\t%s\n' "$target" "$snap/keep.conf" >"$snap/manifest.tsv"
  printf 'broken\n' >"$target"
  env SRV_TUNE_GUARD_BACKEND=nohup SSH_TTY=/dev/pts/3 \
    bash -c 'source "$1"; guard_start g2 1 >/dev/null' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  env SSH_TTY=/dev/pts/4 bash -c 'source "$1"; guard_confirm g2 >/dev/null' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  sleep 2
  [ "$(cat "$target")" = "broken" ]
}

@test "guard survives parent kill -9 (independence from the session)" {
  local stubs
  stubs="$(_make_stubs)"
  local session="$SRV_TUNE_TMP/session.sh"
  cat >"$session" <<EOF
source "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
export SRV_TUNE_STATE_DIR="$SRV_TUNE_STATE_DIR"
export SSH_TTY=/dev/pts/5
export PATH="$stubs:$PATH"
export SRV_TUNE_GUARD_BACKEND=systemd
guard_start k9 300 >/dev/null
sleep 30
EOF
  bash "$session" &
  local pid=$!
  local _try
  for _try in $(seq 1 50); do
    [[ -f "$SRV_TUNE_STATE_DIR/guard/origin-k9.tty" ]] && break
    sleep 0.1
  done
  # The whole session dies violently; the scheduled timer must already exist.
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ -f "$SRV_TUNE_STATE_DIR/guard/origin-k9.tty" ]
  [ -x "$SRV_TUNE_STATE_DIR/guard/revert-k9.sh" ]
  grep -q -- "--on-active=300" "$SRV_TUNE_TMP/systemd-run.log"
}
