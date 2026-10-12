#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# apply wiring: profile + --only + dry-run + stop-on-failure, all sandboxed.
# shellcheck shell=bash

load bats_helper

_setup_apply() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  export OS_RELEASE_FILE="$SRV_TUNE_TMP/os-release"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$SRV_TUNE_TMP/os-release"
  mkdir -p "$SRV_TUNE_TMP/proc/sys/fs"
  printf 'MemTotal:        8192000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf '1048576\n' >"$SRV_TUNE_TMP/proc/sys/fs/nr_open"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  printf 'nameserver 9.9.9.9\n' >"$SRV_TUNE_SYSROOT/etc/resolv.conf"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
}

@test "apply --only limits --dry-run writes no system files" {
  _setup_apply
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only limits --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"why:"* ]]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
}

@test "apply --only limits writes drop-ins and logs the backup" {
  _setup_apply
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only limits --yes
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
  grep -q "module=limits backup=" "$SRV_TUNE_STATE_DIR/applied-changes.log"
}

@test "apply --only bogus fails clearly" {
  _setup_apply
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only bogus --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown module"* ]]
}

@test "apply stops at first failure and keeps files intact" {
  _setup_apply
  cat >"$SRV_TUNE_TMP/stubbin/dig" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/dig"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only dns --yes
  [ "$status" -ne 0 ]
  grep -q "^nameserver 9.9.9.9" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
}

@test "explain prints a module summary" {
  run bash "$SRV_TUNE_ROOT/optimizer.sh" explain limits
  [ "$status" -eq 0 ]
  [[ "$output" == *"nofile"* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" explain bogus
  [ "$status" -ne 0 ]
}

@test "runner calls rollback_live after a failed verify" {
  # Isolated mini-repo: a module whose verify always fails.
  local troot="$SRV_TUNE_TMP/troot"
  mkdir -p "$troot/modules" "$troot/profiles"
  cp -r "$SRV_TUNE_ROOT/lib" "$troot/"
  cat >"$troot/modules/failmod.sh" <<'EOF'
failmod_recommend() { printf 'boom\n'; }
failmod_apply() { printf 'x\n' >"$1/keep.txt"; return 0; }
failmod_verify() { return 1; }
failmod_rollback_live() { printf 'live-cleaned\n' >"$SRV_TUNE_STATE_DIR/live-marker.txt"; }
EOF
  printf 'modules="failmod"\n' >"$troot/profiles/hook.conf"
  run env SRV_TUNE_ROOT="$troot" bash -c 'source "$1/lib/modules.sh"; run_apply hook ""' bash "$troot"
  [ "$status" -ne 0 ]
  [ -f "$SRV_TUNE_STATE_DIR/live-marker.txt" ]
}
