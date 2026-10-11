#!/usr/bin/env bats
# Regression tests for the 3 P1 bugs + strict-mode (set -e/pipefail) audit.
# Bug 1: list_recommendations exited 1 under set -e when the last filter was
#   false (function exit status = failed [[ ]]), aborting scan.sh.
# Bug 2: optimizer.sh used `exec` after lock_acquire, killing the EXIT trap,
#   so the lock was never released. Fixed with trap + no exec.
# Bug 3: missing /run printed a misleading "another run is active" error.
#   Fixed with explicit missing/unwritable handling (TEST-only TMPDIR rule).
# shellcheck shell=bash

load bats_helper

@test "bug1: list_recommendations exits 0 under set -e when all filters false" {
  run env OS_TIER=tier1 SSH_PASS=no SSH_ROOT=no FIREWALL=ufw CC=bbr TUNED=yes AES_NI=yes SWAP_KB=999 \
    bash -c 'set -euo pipefail; source "$1"; out="$(list_recommendations)"; printf "got:[%s]\n" "$out"' bash "$SRV_TUNE_ROOT/scanner/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "got:[]" ]]
}

@test "bug1: list_recommendations prints 8 lines when all filters true" {
  run env OS_TIER=eol SSH_PASS=yes SSH_ROOT=yes FIREWALL=none CC=cubic TUNED=no AES_NI=no SWAP_KB=0 \
    bash -c 'source "$1"; list_recommendations' bash "$SRV_TUNE_ROOT/scanner/report.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 8 ]
}

@test "compute_score exits 0 under set -e and stays within 0-100" {
  run env OS_TIER=eol SSH_PASS=yes SSH_ROOT=yes FIREWALL=none TUNED=no SWAP_KB=0 CC=cubic \
    bash -c 'set -euo pipefail; source "$1"; compute_score' bash "$SRV_TUNE_ROOT/scanner/report.sh"
  [ "$status" -eq 0 ]
  [ "$output" -ge 0 ]
  [ "$output" -le 100 ]
}

@test "preflight getters print unknown for keyless os-release under set -e" {
  printf 'GARBAGE=yes\n' >"$BATS_TMPDIR/os-release"
  run env OS_RELEASE_FILE="$BATS_TMPDIR/os-release" \
    bash -c 'set -euo pipefail; source "$1"; preflight_os_id; preflight_os_version; preflight_os_tier' bash "$SRV_TUNE_ROOT/lib/preflight.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "unknown" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "unknown" ]
  [ "$(printf '%s\n' "$output" | sed -n '3p')" = "unsupported" ]
}

@test "collectors complete under set -e with missing os-release" {
  run env OS_RELEASE_FILE=/nonexistent-os-release \
    bash -c 'set -euo pipefail; source "$1/os.sh"; source "$1/hw.sh"; source "$1/net.sh"; collect_os; collect_hw; collect_net' bash "$SRV_TUNE_ROOT/scanner/collectors"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OS_ID=unknown"* ]]
}

@test "bug2: second acquire fails while held, succeeds after release" {
  run bash -c 'source "$1"; trap lock_release EXIT; lock_acquire && lock_release && lock_acquire && lock_release && echo REACQUIRED' bash "$SRV_TUNE_ROOT/lib/lock.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACQUIRED"* ]]
  run bash -c 'source "$1"; trap lock_release EXIT; lock_acquire; bash -c "source \"$1\"; lock_acquire" bash "$2"' bash "$SRV_TUNE_ROOT/lib/lock.sh" "$SRV_TUNE_ROOT/lib/lock.sh"
  [ "$status" -ne 0 ]
}

@test "bug3: normal mode refuses TMPDIR fallback with a clear error" {
  run env -u SRV_TUNE_TEST SRV_TUNE_LOCK_FILE=/nonexistent-dir-xyz-123/lock \
    bash -c 'source "$1"; lock_acquire' bash "$SRV_TUNE_ROOT/lib/lock.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TEST-only"* ]]
}

@test "bug3: TEST mode falls back to a TMPDIR lock" {
  # Subject is the fallback PATH, not the backend: pin mkdir so flock
  # availability (runner vs container) cannot change what is asserted.
  export SRV_TUNE_LOCK_BACKEND=mkdir
  run env SRV_TUNE_TEST=1 SRV_TUNE_LOCK_FILE=/nonexistent-dir-xyz-123/lock \
    bash -c 'source "$1"; lock_acquire && lock_release && echo FALLBACK-OK' bash "$SRV_TUNE_ROOT/lib/lock.sh"
  unset SRV_TUNE_LOCK_BACKEND
  [ "$status" -eq 0 ]
  [[ "$output" == *"FALLBACK-OK"* ]]
}
