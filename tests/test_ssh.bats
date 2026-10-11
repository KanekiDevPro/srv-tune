#!/usr/bin/env bats
# ssh module: ADMIN key gate, TUNNEL artifacts, validation, guard wiring.
# All file writes go to SYSROOT sandboxes; no daemon is ever touched here.
# shellcheck shell=bash

load bats_helper

_setup_ssh() {
  # $1 = mode (ADMIN|TUNNEL|CUSTOM)
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  export SRV_TUNE_SSH_MODE="$1"
  export SRV_TUNE_SSH_USER=testuser
  export SRV_TUNE_TEST_USER_HOME="$SRV_TUNE_TMP/home/testuser"
  export SRV_TUNE_NO_GUARD=1
  mkdir -p "$SRV_TUNE_TMP/proc" "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d"
  printf 'MemTotal: 1000000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf 'flags : aes\n' >"$SRV_TUNE_TMP/proc/cpuinfo"
  mkdir -p "$SRV_TUNE_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$SRV_TUNE_TEST_USER_HOME/.ssh"
  chmod 600 "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$SRV_TUNE_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit ${SRV_TUNE_STUB_SSHD_RC:-0}
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/sshd"
  export SRV_TUNE_SSHD_BIN="$SRV_TUNE_TMP/stubbin/sshd"
  local realdate realps
  realdate="$(command -v date)"
  realps="$(command -v ps || printf '')"
  cat >"$SRV_TUNE_TMP/stubbin/date" <<EOF
#!/usr/bin/env bash
if [[ -n "\${SRV_TUNE_STUB_DATE:-}" ]]; then printf '%s\n' "\$SRV_TUNE_STUB_DATE"; else exec "$realdate" "\$@"; fi
EOF
  cat >"$SRV_TUNE_TMP/stubbin/ps" <<EOF
#!/usr/bin/env bash
if [[ "\${SRV_TUNE_STUB_ETIMES:-}" == "fail" ]]; then exit 1; fi
if [[ -n "\${SRV_TUNE_STUB_ETIMES:-}" ]]; then printf '%s\n' "\$SRV_TUNE_STUB_ETIMES"; else exec "$realps" "\$@"; fi
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/date" "$SRV_TUNE_TMP/stubbin/ps"
  cat >"$SRV_TUNE_TMP/stubbin/ss" <<'EOF'
#!/usr/bin/env bash
rc=${SRV_TUNE_STUB_SS_RC:-0}
if [[ "$rc" == "0" ]]; then
  printf 'LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:2222 0.0.0.0:*\n'
fi
exit "$rc"
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/ss"
  export SRV_TUNE_SS_BIN="$SRV_TUNE_TMP/stubbin/ss"
  cat >"$SRV_TUNE_TMP/stubbin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/systemctl"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load ssh
}

@test "ssh ADMIN writes a first-match drop-in with key-only auth" {
  _setup_ssh ADMIN
  d="$SRV_TUNE_STATE_DIR/backups/s1"
  mkdir -p "$d"
  run ssh_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  [ -f "$f" ]
  grep -q "^PasswordAuthentication no" "$f"
  grep -q "^PermitRootLogin prohibit-password" "$f"
  grep -q "^MaxAuthTries 3" "$f"
  grep -q "^LoginGraceTime 30" "$f"
  run ssh_verify
  [ "$status" -eq 0 ]
}

@test "ssh ADMIN without a key applies the safe subset and defers the switch" {
  _setup_ssh ADMIN
  rm -f "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  d="$SRV_TUNE_STATE_DIR/backups/s2"
  mkdir -p "$d"
  run ssh_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  [ -f "$f" ]
  grep -q "^MaxAuthTries 3" "$f"
  grep -q "PENDING" "$f"
  run grep -q "^PasswordAuthentication no" "$f"
  [ "$status" -ne 0 ]
  [ -f "$SRV_TUNE_STATE_DIR/guard/pending-s2.lockdown" ]
}

@test "ssh confirm completes the lockdown once a key exists" {
  _setup_ssh ADMIN
  rm -f "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  d="$SRV_TUNE_STATE_DIR/backups/s2b"
  mkdir -p "$d"
  SSH_TTY=/dev/pts/7 SRV_TUNE_STUB_DATE=1000 ssh_apply "$d" >/dev/null
  [ -f "$SRV_TUNE_STATE_DIR/guard/pending-s2b.lockdown" ]
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 600 "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  run env SSH_TTY=/dev/pts/9 SRV_TUNE_STUB_DATE=1100 SRV_TUNE_STUB_ETIMES=5 PATH="$SRV_TUNE_TMP/stubbin:$PATH" \
    bash -c 'source "$1"; guard_confirm s2b' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  grep -q "^PasswordAuthentication no" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  [ ! -f "$SRV_TUNE_STATE_DIR/guard/pending-s2b.lockdown" ]
  [ -f "$SRV_TUNE_STATE_DIR/guard/cancelled-s2b" ]
}

@test "ssh confirm without a key warns and keeps password auth" {
  _setup_ssh ADMIN
  rm -f "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  d="$SRV_TUNE_STATE_DIR/backups/s2c"
  mkdir -p "$d"
  SSH_TTY=/dev/pts/7 SRV_TUNE_STUB_DATE=1000 ssh_apply "$d" >/dev/null
  run env SSH_TTY=/dev/pts/9 SRV_TUNE_STUB_DATE=1100 SRV_TUNE_STUB_ETIMES=5 PATH="$SRV_TUNE_TMP/stubbin:$PATH" \
    bash -c 'source "$1"; guard_confirm s2c' bash "$SRV_TUNE_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"key still missing"* ]]
  run grep -q "^PasswordAuthentication no" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  [ "$status" -ne 0 ]
  [ -f "$SRV_TUNE_STATE_DIR/guard/cancelled-s2c" ]
}

@test "ssh rejects invalid config (failure injection)" {
  _setup_ssh ADMIN
  export SRV_TUNE_STUB_SSHD_RC=1
  d="$SRV_TUNE_STATE_DIR/backups/s3"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_STUB_SSHD_RC
  [ "$status" -ne 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
}

@test "ssh TUNNEL writes forwarding config plus client artifacts" {
  _setup_ssh TUNNEL
  export SRV_TUNE_PERMIT_OPEN="db.internal:5432"
  export SRV_TUNE_SSH_HOST="example.com"
  d="$SRV_TUNE_STATE_DIR/backups/s4"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_PERMIT_OPEN SRV_TUNE_SSH_HOST
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  grep -q "^AllowTcpForwarding yes" "$f"
  grep -q "^Compression no" "$f"
  grep -q "PermitOpen" "$f"
  [ -f "$SRV_TUNE_STATE_DIR/ssh-client-example.com.conf" ]
  [ -f "$SRV_TUNE_STATE_DIR/autossh-tunnel.service" ]
}

@test "ssh CUSTOM appends an operator snippet after validation" {
  _setup_ssh CUSTOM
  printf 'Banner /etc/issue.net\n' >"$SRV_TUNE_TMP/custom.snip"
  export SRV_TUNE_SSH_CUSTOM_SRC="$SRV_TUNE_TMP/custom.snip"
  d="$SRV_TUNE_STATE_DIR/backups/s5"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_SSH_CUSTOM_SRC
  [ "$status" -eq 0 ]
  grep -q "^Banner /etc/issue.net" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
}

@test "ssh CUSTOM rejects unknown keywords" {
  _setup_ssh CUSTOM
  printf 'EvilDirective yes\n' >"$SRV_TUNE_TMP/custom.snip"
  export SRV_TUNE_SSH_CUSTOM_SRC="$SRV_TUNE_TMP/custom.snip"
  d="$SRV_TUNE_STATE_DIR/backups/s6"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_SSH_CUSTOM_SRC
  [ "$status" -ne 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
}

@test "ssh TUNNEL tun mode in vpn-tunnel writes ip_forward, elsewhere not" {
  _setup_ssh TUNNEL
  export SRV_TUNE_TUNNEL_MODE=tun
  export SRV_TUNE_PROFILE=vpn-tunnel
  d="$SRV_TUNE_STATE_DIR/backups/s9"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_TUNNEL_MODE SRV_TUNE_PROFILE
  [ "$status" -eq 0 ]
  grep -q "^net.ipv4.ip_forward=1" "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune-tun.conf"
}

@test "ssh TUNNEL outside vpn-tunnel writes no forwarding knobs" {
  _setup_ssh TUNNEL
  export SRV_TUNE_TUNNEL_MODE=tun
  export SRV_TUNE_PROFILE=generic
  d="$SRV_TUNE_STATE_DIR/backups/s10"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_TUNNEL_MODE SRV_TUNE_PROFILE
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune-tun.conf" ]
}

@test "ssh port change writes a socket override" {
  _setup_ssh ADMIN
  export SRV_TUNE_SSH_PORT=2222
  d="$SRV_TUNE_STATE_DIR/backups/s7"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_SSH_PORT
  [ "$status" -eq 0 ]
  grep -q "^Port 22" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  grep -q "^Port 2222" "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  grep -q "ListenStream=2222" "$SRV_TUNE_SYSROOT/etc/systemd/system/ssh.socket.d/00-srv-tune.conf"
}

@test "ssh fails when the new port never listens (injection)" {
  _setup_ssh ADMIN
  export SRV_TUNE_SSH_PORT=2222
  export SRV_TUNE_STUB_SS_RC=1
  d="$SRV_TUNE_STATE_DIR/backups/s8"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset SRV_TUNE_SSH_PORT SRV_TUNE_STUB_SS_RC
  [ "$status" -ne 0 ]
  [[ "$output" == *"not listening"* ]]
}
