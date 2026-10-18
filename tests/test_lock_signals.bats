#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Lock release on normal exit, error, INT and TERM — every available backend.
# flock backend: kernel frees fd locks on death; mkdir backend relies on the
# trap (TEMPER_LOCK_BACKEND=mkdir forces it portably).
# shellcheck shell=bash

load bats_helper

_backends() {
  # Prints one backend per line: always mkdir; flock only if present.
  printf 'mkdir\n'
  if command -v flock >/dev/null 2>&1; then
    printf 'flock\n'
  fi
}

_write_holder() {
  # $1 = lock file, $2 = ready file, $3 = backend, $4 = body (sleep|exit|fail)
  local lock="$1" ready="$2" backend="$3" body="$4"
  local h="$TEMPER_TMP/holder.sh"
  cat >"$h" <<EOF
source "$TEMPER_ROOT/lib/lock.sh"
export TEMPER_LOCK_FILE="$lock"
export TEMPER_TEST=1
export TEMPER_LOCK_BACKEND="$backend"
lock_acquire || exit 3
printf 'ready\n' >"$ready"
trap lock_release EXIT INT TERM
$body
EOF
  printf '%s\n' "$h"
}

_wait_ready() {
  local ready="$1" _try
  for _try in $(seq 1 100); do
    [[ -f "$ready" ]] && return 0
    sleep 0.1
  done
  return 1
}

_lock_free() {
  # Re-acquire in a fresh process: proves the previous holder released.
  bash -c 'source "$1"; lock_acquire && lock_release' bash "$TEMPER_ROOT/lib/lock.sh"
}

@test "lock released on normal exit (all backends)" {
  local backend
  while IFS= read -r backend; do
    local lock="$TEMPER_TMP/norm-$backend.lock" ready="$TEMPER_TMP/norm-$backend.ready"
    local h
    h="$(_write_holder "$lock" "$ready" "$backend" 'exit 0')"
    TEMPER_LOCK_BACKEND="$backend" bash "$h"
    TEMPER_LOCK_FILE="$lock" TEMPER_LOCK_BACKEND="$backend" _lock_free
  done < <(_backends)
}

@test "lock released on error exit, set -e plus EXIT trap (all backends)" {
  local backend
  while IFS= read -r backend; do
    local lock="$TEMPER_TMP/err-$backend.lock" ready="$TEMPER_TMP/err-$backend.ready"
    local h
    h="$(_write_holder "$lock" "$ready" "$backend" 'set -e; false; echo UNREACHABLE')"
    run env TEMPER_LOCK_BACKEND="$backend" bash "$h"
    [ "$status" -ne 0 ]
    TEMPER_LOCK_FILE="$lock" TEMPER_LOCK_BACKEND="$backend" _lock_free
  done < <(_backends)
}

@test "lock released on TERM (all backends)" {
  local backend
  while IFS= read -r backend; do
    local lock="$TEMPER_TMP/term-$backend.lock" ready="$TEMPER_TMP/term-$backend.ready"
    local h
    h="$(_write_holder "$lock" "$ready" "$backend" 'sleep 10')"
    env TEMPER_LOCK_BACKEND="$backend" bash "$h" &
    local pid=$!
    _wait_ready "$ready" || {
      kill "$pid" 2>/dev/null || true
      return 1
    }
    kill -TERM "$pid"
    wait "$pid" || true
    TEMPER_LOCK_FILE="$lock" TEMPER_LOCK_BACKEND="$backend" _lock_free
  done < <(_backends)
}

@test "lock released on INT (all backends)" {
  local backend
  while IFS= read -r backend; do
    local lock="$TEMPER_TMP/int-$backend.lock" ready="$TEMPER_TMP/int-$backend.ready"
    local h
    h="$(_write_holder "$lock" "$ready" "$backend" 'sleep 10')"
    env TEMPER_LOCK_BACKEND="$backend" bash "$h" &
    local pid=$!
    _wait_ready "$ready" || {
      kill "$pid" 2>/dev/null || true
      return 1
    }
    kill -INT "$pid"
    wait "$pid" || true
    TEMPER_LOCK_FILE="$lock" TEMPER_LOCK_BACKEND="$backend" _lock_free
  done < <(_backends)
}

@test "second acquire fails while the lock is held" {
  local lock="$TEMPER_TMP/held.lock" ready="$TEMPER_TMP/held.ready"
  local h
  h="$(_write_holder "$lock" "$ready" 'mkdir' 'sleep 10')"
  env TEMPER_LOCK_BACKEND=mkdir bash "$h" &
  local pid=$!
  _wait_ready "$ready" || {
    kill "$pid" 2>/dev/null || true
    return 1
  }
  run env TEMPER_LOCK_FILE="$lock" TEMPER_LOCK_BACKEND=mkdir bash -c 'source "$1"; lock_acquire' bash "$TEMPER_ROOT/lib/lock.sh"
  kill "$pid"
  wait "$pid" || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"another temper run is active"* ]]
}

@test "refuse_world_writable blocks root on world-writable dirs" {
  mkdir -p "$TEMPER_TMP/ww"
  chmod 777 "$TEMPER_TMP/ww"
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/lib/util.sh"
  if ! path_is_world_writable "$TEMPER_TMP/ww"; then
    skip "host ignores chmod 777 (Windows ACLs); covered on Linux CI"
  fi
  # Fake root: the branch is testable without uid 0.
  run bash -c 'source "$1"; is_root() { return 0; }; refuse_world_writable "$2" "lock dir"' bash "$TEMPER_ROOT/lib/util.sh" "$TEMPER_TMP/ww"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing world-writable"* ]]
  # Real callers: root is refused, non-root passes.
  run bash -c 'source "$1"; refuse_world_writable "$2" "lock dir"' bash "$TEMPER_ROOT/lib/util.sh" "$TEMPER_TMP/ww"
  if [[ "$(id -u)" == "0" ]]; then
    [ "$status" -ne 0 ]
  else
    [ "$status" -eq 0 ]
  fi
}
