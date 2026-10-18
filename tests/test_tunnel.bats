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

@test "tunnel --help prints usage" {
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"srv-tune tunnel"* ]]
  [[ "$output" == *"keys"* ]]
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
ESTAB 0 0 10.0.0.1:2222 198.51.100.8:52000 users:(("sshd",pid=4343,fd=3))
ESTAB 0 0 10.0.0.1:80 203.0.113.9:53000 users:(("nginx",pid=99,fd=3))
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
  [[ "$output" != *"198.51.100.8"* ]]
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

_tunnel_access_stubs() {
  local dir="$SRV_TUNE_TMP/stubbin"
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit 0\n' >"$dir/sshd"
  # ssh_wait_port greps ":<port> "; emit rows for 22 and a custom 2222.
  printf '#!/bin/sh\nprintf "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\\nLISTEN 0 128 0.0.0.0:2222 0.0.0.0:*\\n"\n' >"$dir/ss"
  chmod +x "$dir/sshd" "$dir/ss"
  export SRV_TUNE_SSHD_BIN="$dir/sshd"
  export SRV_TUNE_SS_BIN="$dir/ss"
  export SRV_TUNE_NO_GUARD=1
}

@test "tunnel access set rewrites policy and preserves port and user" {
  _tunnel_setup
  _tunnel_access_stubs
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access set \
    --permit-open db.internal:5432,git.internal:22 --gateway-ports yes --yes
  [ "$status" -eq 0 ]
  local f="$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  run grep -q 'PermitOpen db.internal:5432,git.internal:22' "$f"
  [ "$status" -eq 0 ]
  run grep -q '^GatewayPorts yes' "$f"
  [ "$status" -eq 0 ]
  run grep -q '^Port 22' "$f"
  [ "$status" -eq 0 ]
  run grep -q '^Match User tunnel' "$f"
  [ "$status" -eq 0 ]
  ls "$SRV_TUNE_STATE_DIR"/backups/*/manifest.tsv >/dev/null
}

@test "tunnel access set refuses when no tunnel drop-in is applied" {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_TEST=1
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access set \
    --permit-open none --gateway-ports no --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a tunnel server"* ]]
}

@test "tunnel access set rejects a malformed permit-open" {
  _tunnel_setup
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access set \
    --permit-open 'bad target' --gateway-ports no --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"permit-open"* ]]
}

@test "tunnel access show reports the applied policy" {
  _tunnel_setup
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access show
  [ "$status" -eq 0 ]
  [[ "$output" == *"permit_open: db.internal:5432"* ]]
  [[ "$output" == *"gateway_ports: no"* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access show --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permit_tunnel":false'* ]]
}

_tunnel_setup_custom_port() {
  _tunnel_setup
  cat >"$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" <<'EOF'
# srv-tune TUNNEL (why: forwarding server, no shell)
Port 22
Port 2222
GatewayPorts no
PermitTunnel yes
Match User tunnel
  PermitTTY no
  ForceCommand /usr/sbin/nologin
  PermitOpen db.internal:5432
EOF
}

@test "tunnel access set preserves a custom port listed after Port 22" {
  _tunnel_setup_custom_port
  _tunnel_access_stubs
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel status --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"port":"2222"'* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel access set \
    --permit-open git.internal:2222 --gateway-ports no --yes
  [ "$status" -eq 0 ]
  local f="$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  run grep -q '^Port 22$' "$f"
  [ "$status" -eq 0 ]
  run grep -q '^Port 2222$' "$f"
  [ "$status" -eq 0 ]
  run grep -q 'PermitOpen git.internal:2222' "$f"
  [ "$status" -eq 0 ]
  run grep -q '^PermitTunnel yes$' "$f"
  [ "$status" -eq 0 ]
}

@test "tunnel sessions match every port in the drop-in" {
  _tunnel_setup_custom_port
  local stub="$SRV_TUNE_TMP/ss-ports"
  cat >"$stub" <<'EOF'
#!/usr/bin/env bash
cat <<'ROWS'
State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
ESTAB 0 0 10.0.0.1:22 198.51.100.7:51000 users:(("sshd",pid=4242,fd=3))
ESTAB 0 0 10.0.0.1:2222 198.51.100.8:52000 users:(("sshd",pid=4343,fd=3))
ESTAB 0 0 [::1]:2222 2001:db8::1:53000 users:(("sshd",pid=4444,fd=3))
ESTAB 0 0 10.0.0.1:80 203.0.113.9:53000 users:(("nginx",pid=99,fd=3))
ROWS
EOF
  chmod +x "$stub"
  export SRV_TUNE_SS_BIN="$stub"
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel sessions
  [ "$status" -eq 0 ]
  [[ "$output" == *"198.51.100.7:51000 pid=4242"* ]]
  [[ "$output" == *"198.51.100.8:52000 pid=4343"* ]]
  [[ "$output" == *"2001:db8::1:53000 pid=4444"* ]]
  [[ "$output" != *"nginx"* ]]
}

@test "tunnel sessions notes the port-22 assumption when the drop-in has no Port" {
  _tunnel_setup
  cat >"$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" <<'EOF'
# srv-tune TUNNEL (why: forwarding server, no shell)
GatewayPorts no
PermitTunnel no
Match User tunnel
  PermitTTY no
  ForceCommand /usr/sbin/nologin
  PermitOpen db.internal:5432
EOF
  _tunnel_ss_stub
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel sessions
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Port in the drop-in"* ]]
  [[ "$output" == *"198.51.100.7:51000 pid=4242"* ]]
  [[ "$output" != *"198.51.100.8"* ]]
}

@test "tunnel access set keeps its environment scoped to the call" {
  _tunnel_setup_custom_port
  _tunnel_access_stubs
  run bash -c '
    set -u
    source "$SRV_TUNE_ROOT/lib/tunnel.sh"
    run_apply() { return 0; }
    tunnel_access_set --permit-open db.internal:5432 --gateway-ports no --yes
    rc=$?
    printf "rc=%s assume=[%s] ssh_port=[%s] profile=[%s] mode=[%s]\n" \
      "$rc" "${SRV_TUNE_ASSUME_YES:-}" "${SRV_TUNE_SSH_PORT:-}" \
      "${SRV_TUNE_PROFILE:-}" "${SRV_TUNE_SSH_MODE:-}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0 assume=[] ssh_port=[] profile=[] mode=[]"* ]]
}

@test "tunnel keys add and remove refuse while another run holds the lock" {
  _tunnel_setup
  _tunnel_keygen
  local marker="$SRV_TUNE_TMP/lock-held" hold i=0
  bash -c '
    source "$SRV_TUNE_ROOT/lib/lock.sh"
    lock_acquire || exit 1
    : >"$1"
    sleep 10
  ' bash "$marker" &
  hold=$!
  while [[ ! -f "$marker" && "$i" -lt 50 ]]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -f "$marker" ]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys add <<<"$KEY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"another srv-tune run"* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" tunnel keys remove --fp SHA256:abc
  kill "$hold" 2>/dev/null || true
  wait "$hold" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"another srv-tune run"* ]]
}
