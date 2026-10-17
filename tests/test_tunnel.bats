#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Tunnel core: status from the applied drop-in, key lifecycle, sessions,
# access edits, non-tty behavior. Sandboxed (SYSROOT + fake home).
# shellcheck shell=bash

load bats_helper

_tunnel_setup() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_TUNNEL_USER=tunnel
  export SRV_TUNE_TUNNEL_HOME="$SRV_TUNE_TMP/home/tunnel"
  mkdir -p "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d"
  mkdir -p "$SRV_TUNE_TUNNEL_HOME/.ssh"
  chmod 700 "$SRV_TUNE_TUNNEL_HOME/.ssh"
  cat >"$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" <<'EOF'
# srv-tune TUNNEL (why: forwarding server, no shell)
Port 22
GatewayPorts no
PermitTunnel no
Match User tunnel
  PermitTTY no
  ForceCommand /usr/sbin/nologin
  PermitOpen db.internal:5432
EOF
}

@test "tunnel status renders the applied drop-in" {
  _tunnel_setup
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: TUNNEL"* ]]
  [[ "$output" == *"permit_open: db.internal:5432"* ]]
  [[ "$output" == *"dropin: $SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf (present)"* ]]
}

@test "tunnel status --json is machine readable" {
  _tunnel_setup
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel status --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"TUNNEL"'* ]]
  [[ "$output" == *'"permit_open":"db.internal:5432"'* ]]
  [[ "$output" == *'"gateway_ports":false'* ]]
}

@test "tunnel status reports an absent drop-in without failing" {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: absent"* ]]
  [[ "$output" == *"(absent)"* ]]
}

@test "tunnel has no tty: prints status instead of a menu" {
  _tunnel_setup
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: TUNNEL"* ]]
}
