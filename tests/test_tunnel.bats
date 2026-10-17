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

_tunnel_keygen() {
  command -v ssh-keygen >/dev/null 2>&1 || skip "ssh-keygen not installed"
  ssh-keygen -q -t ed25519 -N '' -f "$SRV_TUNE_TMP/id_test" >/dev/null
  KEY="$(cat "$SRV_TUNE_TMP/id_test.pub")"
}

_chmod_effective() {
  local probe="$SRV_TUNE_TMP/permprobe"
  printf 'x\n' >"$probe"
  chmod 600 "$probe" 2>/dev/null || return 1
  [[ "$(stat -c '%a' "$probe" 2>/dev/null)" == "600" ]]
}

@test "tunnel keys add from stdin stores the key with safe perms" {
  _tunnel_setup
  _tunnel_keygen
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add --comment laptop <<<"$KEY"
  [ "$status" -eq 0 ]
  local f="$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys"
  grep -q 'laptop' "$f"
  if _chmod_effective; then
    [ "$(stat -c '%a' "$f")" = "600" ]
    [ "$(stat -c '%a' "$(dirname "$f")")" = "700" ]
  fi
  ls "$SRV_TUNE_STATE_DIR"/backups/keys-* >/dev/null
  grep -q 'action=key-add' "$SRV_TUNE_STATE_DIR/tunnel-actions.log"
}

@test "tunnel keys add refuses a duplicate" {
  _tunnel_setup
  _tunnel_keygen
  mkdir -p "$SRV_TUNE_TUNNEL_HOME/.ssh"
  printf '%s\n' "$KEY" >"$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add <<<"$KEY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already present"* ]]
  [ "$(grep -c 'ssh-ed25519' "$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys")" -eq 1 ]
}

@test "tunnel keys add rejects an invalid key and leaves the file untouched" {
  _tunnel_setup
  printf '%s\n' "not-a-key" >"$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add <<<"not-a-key"
  [ "$status" -eq 1 ]
  [ "$(cat "$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys")" = "not-a-key" ]
}

@test "tunnel keys add --comment replaces the trailing comment" {
  _tunnel_setup
  _tunnel_keygen
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add --comment office <<<"$KEY"
  [ "$status" -eq 0 ]
  run grep -q ' office$' "$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys"
  [ "$status" -eq 0 ]
}

@test "tunnel keys remove deletes by fingerprint" {
  _tunnel_setup
  _tunnel_keygen
  bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add --comment laptop <<<"$KEY" >/dev/null
  fp="$(ssh-keygen -lf "$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys" | awk '{print $2}')"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys remove --fp "$fp"
  [ "$status" -eq 0 ]
  [ ! -s "$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys" ]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys remove --fp "$fp"
  [ "$status" -eq 1 ]
}

@test "tunnel keys add --file and keys list --json agree on the key" {
  _tunnel_setup
  _tunnel_keygen
  cp "$SRV_TUNE_TMP/id_test.pub" "$SRV_TUNE_TMP/in.pub"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add --file "$SRV_TUNE_TMP/in.pub" --comment router
  [ "$status" -eq 0 ]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"type":"ED25519"'* ]]
  [[ "$output" == *'"fp":"SHA256:'* ]]
  [[ "$output" == *router* ]]
}

_tunnel_ss_stub() {
  local stub="$SRV_TUNE_TMP/ss-stub"
  cat >"$stub" <<'EOF'
#!/usr/bin/env bash
cat <<'ROWS'
State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
ESTAB 0 0 10.0.0.1:22 198.51.100.7:51000 users:(("sshd",pid=4242,fd=3))
ESTAB 0 0 10.0.0.1:80 203.0.113.9:52000 users:(("nginx",pid=99,fd=3))
ROWS
EOF
  chmod +x "$stub"
  export SRV_TUNE_SS_BIN="$stub"
}

@test "tunnel sessions lists only ssh connections" {
  _tunnel_setup
  _tunnel_ss_stub
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel sessions
  [ "$status" -eq 0 ]
  [[ "$output" == *"198.51.100.7:51000 pid=4242"* ]]
  [[ "$output" != *"nginx"* ]]
  [[ "$output" != *"203.0.113.9"* ]]
}

@test "tunnel sessions --json is machine readable and status counts them" {
  _tunnel_setup
  _tunnel_ss_stub
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel sessions --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"peer":"198.51.100.7:51000"'* ]]
  [[ "$output" == *'"pid":"4242"'* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel status
  [ "$status" -eq 0 ]
  [[ "$output" == *"sessions: 1"* ]]
}
