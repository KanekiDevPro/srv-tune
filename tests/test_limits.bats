#!/usr/bin/env bats
# limits module: computed values, sandboxed apply, verify, dry-run.
# shellcheck shell=bash

load bats_helper

_setup_sysroot() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  mkdir -p "$SRV_TUNE_TMP/proc/sys/fs" "$SRV_TUNE_TMP/proc"
  printf 'MemTotal:        8192000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf '1048576\n' >"$SRV_TUNE_TMP/proc/sys/fs/nr_open"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load limits
}

@test "limits values respect the nr_open cap" {
  _setup_sysroot
  printf '4096\n' >"$SRV_TUNE_TMP/proc/sys/fs/nr_open"
  run limits_values
  [ "$status" -eq 0 ]
  hard="$(printf '%s' "$output" | awk '{print $1}')"
  [ "$hard" -le 4096 ]
}

@test "limits apply writes three drop-ins plus coredump off" {
  _setup_sysroot
  d="$SRV_TUNE_STATE_DIR/backups/l1"
  mkdir -p "$d"
  run limits_apply "$d"
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
  [ -f "$SRV_TUNE_SYSROOT/etc/systemd/system.conf.d/00-srv-tune.conf" ]
  [ -f "$SRV_TUNE_SYSROOT/etc/systemd/user.conf.d/00-srv-tune.conf" ]
  [ -f "$SRV_TUNE_SYSROOT/etc/systemd/coredump.conf.d/00-srv-tune.conf" ]
  run limits_verify
  [ "$status" -eq 0 ]
}

@test "limits apply is idempotent (second run changes nothing)" {
  _setup_sysroot
  d1="$SRV_TUNE_STATE_DIR/backups/l1"
  d2="$SRV_TUNE_STATE_DIR/backups/l2"
  mkdir -p "$d1" "$d2"
  limits_apply "$d1"
  sum1="$(cat "$SRV_TUNE_SYSROOT"/etc/security/limits.d/00-srv-tune.conf)"
  limits_apply "$d2"
  sum2="$(cat "$SRV_TUNE_SYSROOT"/etc/security/limits.d/00-srv-tune.conf)"
  [ "$sum1" = "$sum2" ]
}

@test "limits dry-run writes nothing" {
  _setup_sysroot
  d="$SRV_TUNE_STATE_DIR/backups/l9"
  mkdir -p "$d"
  printf 'a=2\n' >"$SRV_TUNE_TMP/new.conf"
  export SRV_TUNE_DRY_RUN=1
  run limits_apply "$d"
  unset SRV_TUNE_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
}

@test "limits debug opt-in keeps core dumps enabled" {
  _setup_sysroot
  d="$SRV_TUNE_STATE_DIR/backups/l3"
  mkdir -p "$d"
  export SRV_TUNE_DEBUG=1
  run limits_apply "$d"
  unset SRV_TUNE_DEBUG
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/systemd/coredump.conf.d/00-srv-tune.conf" ]
}
