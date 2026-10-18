#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# limits module: computed values, sandboxed apply, verify, dry-run.
# shellcheck shell=bash

load bats_helper

_setup_sysroot() {
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  mkdir -p "$TEMPER_TMP/proc/sys/fs" "$TEMPER_TMP/proc"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf '1048576\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/lib/modules.sh"
  module_load limits
}

@test "limits values respect the nr_open cap" {
  _setup_sysroot
  printf '4096\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
  run limits_values
  [ "$status" -eq 0 ]
  hard="$(printf '%s' "$output" | awk '{print $1}')"
  [ "$hard" -le 4096 ]
}

@test "limits apply writes three drop-ins plus coredump off" {
  _setup_sysroot
  d="$TEMPER_STATE_DIR/backups/l1"
  mkdir -p "$d"
  run limits_apply "$d"
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
  [ -f "$TEMPER_SYSROOT/etc/systemd/system.conf.d/00-temper.conf" ]
  [ -f "$TEMPER_SYSROOT/etc/systemd/user.conf.d/00-temper.conf" ]
  [ -f "$TEMPER_SYSROOT/etc/systemd/coredump.conf.d/00-temper.conf" ]
  run limits_verify
  [ "$status" -eq 0 ]
}

@test "limits apply is idempotent (second run changes nothing)" {
  _setup_sysroot
  d1="$TEMPER_STATE_DIR/backups/l1"
  d2="$TEMPER_STATE_DIR/backups/l2"
  mkdir -p "$d1" "$d2"
  limits_apply "$d1"
  sum1="$(cat "$TEMPER_SYSROOT"/etc/security/limits.d/00-temper.conf)"
  limits_apply "$d2"
  sum2="$(cat "$TEMPER_SYSROOT"/etc/security/limits.d/00-temper.conf)"
  [ "$sum1" = "$sum2" ]
}

@test "limits dry-run writes nothing" {
  _setup_sysroot
  d="$TEMPER_STATE_DIR/backups/l9"
  mkdir -p "$d"
  printf 'a=2\n' >"$TEMPER_TMP/new.conf"
  export TEMPER_DRY_RUN=1
  run limits_apply "$d"
  unset TEMPER_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "limits debug opt-in keeps core dumps enabled" {
  _setup_sysroot
  d="$TEMPER_STATE_DIR/backups/l3"
  mkdir -p "$d"
  export TEMPER_DEBUG=1
  run limits_apply "$d"
  unset TEMPER_DEBUG
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/systemd/coredump.conf.d/00-temper.conf" ]
}
