#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# apply wiring: profile + --only + dry-run + stop-on-failure, all sandboxed.
# shellcheck shell=bash

load bats_helper

_setup_apply() {
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  export OS_RELEASE_FILE="$TEMPER_TMP/os-release"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$TEMPER_TMP/os-release"
  mkdir -p "$TEMPER_TMP/proc/sys/fs"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf '1048576\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
  mkdir -p "$TEMPER_TMP/stubbin" "$TEMPER_SYSROOT/etc"
  printf 'nameserver 9.9.9.9\n' >"$TEMPER_SYSROOT/etc/resolv.conf"
  export PATH="$TEMPER_TMP/stubbin:$PATH"
}

@test "apply --only limits --dry-run writes no system files" {
  _setup_apply
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only limits --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"why:"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "apply --only limits writes drop-ins and logs the backup" {
  _setup_apply
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only limits --yes
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
  grep -q "module=limits backup=" "$TEMPER_STATE_DIR/applied-changes.log"
}

@test "apply --only bogus fails clearly" {
  _setup_apply
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only bogus --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown module"* ]]
}

@test "apply stops at first failure and keeps files intact" {
  _setup_apply
  cat >"$TEMPER_TMP/stubbin/dig" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
  chmod +x "$TEMPER_TMP/stubbin/dig"
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only dns --yes
  [ "$status" -ne 0 ]
  grep -q "^nameserver 9.9.9.9" "$TEMPER_SYSROOT/etc/resolv.conf"
}

@test "explain prints a module summary" {
  run bash "$TEMPER_ROOT/optimizer.sh" explain limits
  [ "$status" -eq 0 ]
  [[ "$output" == *"nofile"* ]]
  run bash "$TEMPER_ROOT/optimizer.sh" explain bogus
  [ "$status" -ne 0 ]
}

@test "runner calls rollback_live after a failed verify" {
  # Isolated mini-repo: a module whose verify always fails.
  local troot="$TEMPER_TMP/troot"
  mkdir -p "$troot/modules" "$troot/profiles"
  cp -r "$TEMPER_ROOT/lib" "$troot/"
  cat >"$troot/modules/failmod.sh" <<'EOF'
failmod_recommend() { printf 'boom\n'; }
failmod_apply() { printf 'x\n' >"$1/keep.txt"; return 0; }
failmod_verify() { return 1; }
failmod_rollback_live() { printf 'live-cleaned\n' >"$TEMPER_STATE_DIR/live-marker.txt"; }
EOF
  printf 'modules="failmod"\n' >"$troot/profiles/hook.conf"
  run env TEMPER_ROOT="$troot" bash -c 'source "$1/lib/modules.sh"; run_apply hook ""' bash "$troot"
  [ "$status" -ne 0 ]
  [ -f "$TEMPER_STATE_DIR/live-marker.txt" ]
}
