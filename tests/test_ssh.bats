#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# ssh module: ADMIN key gate, TUNNEL artifacts, validation, guard wiring.
# All file writes go to SYSROOT sandboxes; no daemon is ever touched here.
# shellcheck shell=bash

load bats_helper

_setup_ssh() {
  # $1 = mode (ADMIN|TUNNEL|CUSTOM)
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  export TEMPER_SSH_MODE="$1"
  export TEMPER_SSH_USER=testuser
  export TEMPER_TEST_USER_HOME="$TEMPER_TMP/home/testuser"
  export TEMPER_NO_GUARD=1
  mkdir -p "$TEMPER_TMP/proc" "$TEMPER_TMP/stubbin" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d"
  printf 'MemTotal: 1000000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf 'flags : aes\n' >"$TEMPER_TMP/proc/cpuinfo"
  mkdir -p "$TEMPER_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$TEMPER_TEST_USER_HOME/.ssh"
  chmod 600 "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$TEMPER_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit ${TEMPER_STUB_SSHD_RC:-0}
EOF
  chmod +x "$TEMPER_TMP/stubbin/sshd"
  export TEMPER_SSHD_BIN="$TEMPER_TMP/stubbin/sshd"
  local realdate realps
  realdate="$(command -v date)"
  realps="$(command -v ps || printf '')"
  cat >"$TEMPER_TMP/stubbin/date" <<EOF
#!/usr/bin/env bash
if [[ -n "\${TEMPER_STUB_DATE:-}" ]]; then printf '%s\n' "\$TEMPER_STUB_DATE"; else exec "$realdate" "\$@"; fi
EOF
  cat >"$TEMPER_TMP/stubbin/ps" <<EOF
#!/usr/bin/env bash
if [[ "\${TEMPER_STUB_ETIMES:-}" == "fail" ]]; then exit 1; fi
if [[ -n "\${TEMPER_STUB_ETIMES:-}" ]]; then printf '%s\n' "\$TEMPER_STUB_ETIMES"; else exec "$realps" "\$@"; fi
EOF
  chmod +x "$TEMPER_TMP/stubbin/date" "$TEMPER_TMP/stubbin/ps"
  cat >"$TEMPER_TMP/stubbin/systemd-run" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEMPER_TMP/systemd-run.log"
exit 0
EOF
  chmod +x "$TEMPER_TMP/stubbin/systemd-run"
  cat >"$TEMPER_TMP/stubbin/ss" <<'EOF'
#!/usr/bin/env bash
rc=${TEMPER_STUB_SS_RC:-0}
if [[ "$rc" == "0" ]]; then
  printf 'LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:2222 0.0.0.0:*\n'
fi
exit "$rc"
EOF
  chmod +x "$TEMPER_TMP/stubbin/ss"
  export TEMPER_SS_BIN="$TEMPER_TMP/stubbin/ss"
  cat >"$TEMPER_TMP/stubbin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$TEMPER_TMP/stubbin/systemctl"
  export PATH="$TEMPER_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/lib/modules.sh"
  module_load ssh
}

@test "ssh ADMIN writes a first-match drop-in with key-only auth" {
  _setup_ssh ADMIN
  d="$TEMPER_STATE_DIR/backups/s1"
  mkdir -p "$d"
  run ssh_apply "$d"
  [ "$status" -eq 0 ]
  f="$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
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
  rm -f "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  d="$TEMPER_STATE_DIR/backups/s2"
  mkdir -p "$d"
  run ssh_apply "$d"
  [ "$status" -eq 0 ]
  f="$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  [ -f "$f" ]
  grep -q "^MaxAuthTries 3" "$f"
  grep -q "PENDING" "$f"
  run grep -q "^PasswordAuthentication no" "$f"
  [ "$status" -ne 0 ]
  [ -f "$TEMPER_STATE_DIR/guard/pending-s2.lockdown" ]
}

@test "ssh confirm completes the lockdown once a key exists" {
  _setup_ssh ADMIN
  rm -f "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  d="$TEMPER_STATE_DIR/backups/s2b"
  mkdir -p "$d"
  SSH_TTY=/dev/pts/7 TEMPER_STUB_DATE=1000 ssh_apply "$d" >/dev/null
  [ -f "$TEMPER_STATE_DIR/guard/pending-s2b.lockdown" ]
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 600 "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  run env SSH_TTY=/dev/pts/9 TEMPER_STUB_DATE=1100 TEMPER_STUB_ETIMES=5 PATH="$TEMPER_TMP/stubbin:$PATH" \
    bash -c 'source "$1"; guard_confirm s2b' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  grep -q "^PasswordAuthentication no" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  [ ! -f "$TEMPER_STATE_DIR/guard/pending-s2b.lockdown" ]
  [ -f "$TEMPER_STATE_DIR/guard/cancelled-s2b" ]
}

@test "ssh confirm without a key warns and keeps password auth" {
  _setup_ssh ADMIN
  rm -f "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  d="$TEMPER_STATE_DIR/backups/s2c"
  mkdir -p "$d"
  SSH_TTY=/dev/pts/7 TEMPER_STUB_DATE=1000 ssh_apply "$d" >/dev/null
  run env SSH_TTY=/dev/pts/9 TEMPER_STUB_DATE=1100 TEMPER_STUB_ETIMES=5 PATH="$TEMPER_TMP/stubbin:$PATH" \
    bash -c 'source "$1"; guard_confirm s2c' bash "$TEMPER_ROOT/lib/ssh-guard.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"key still missing"* ]]
  run grep -q "^PasswordAuthentication no" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  [ "$status" -ne 0 ]
  [ -f "$TEMPER_STATE_DIR/guard/cancelled-s2c" ]
}

@test "ssh rejects invalid config (failure injection)" {
  _setup_ssh ADMIN
  export TEMPER_STUB_SSHD_RC=1
  d="$TEMPER_STATE_DIR/backups/s3"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_STUB_SSHD_RC
  [ "$status" -ne 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
}

@test "ssh TUNNEL writes forwarding config plus client artifacts" {
  _setup_ssh TUNNEL
  export TEMPER_PERMIT_OPEN="db.internal:5432"
  export TEMPER_SSH_HOST="example.com"
  d="$TEMPER_STATE_DIR/backups/s4"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_PERMIT_OPEN TEMPER_SSH_HOST
  [ "$status" -eq 0 ]
  f="$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  grep -q "^AllowTcpForwarding yes" "$f"
  grep -q "^Compression no" "$f"
  grep -q "PermitOpen" "$f"
  [ -f "$TEMPER_STATE_DIR/ssh-client-example.com.conf" ]
  [ -f "$TEMPER_STATE_DIR/autossh-tunnel.service" ]
}

@test "ssh CUSTOM appends an operator snippet after validation" {
  _setup_ssh CUSTOM
  printf 'Banner /etc/issue.net\n' >"$TEMPER_TMP/custom.snip"
  export TEMPER_SSH_CUSTOM_SRC="$TEMPER_TMP/custom.snip"
  d="$TEMPER_STATE_DIR/backups/s5"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_SSH_CUSTOM_SRC
  [ "$status" -eq 0 ]
  grep -q "^Banner /etc/issue.net" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
}

@test "ssh CUSTOM rejects unknown keywords" {
  _setup_ssh CUSTOM
  printf 'EvilDirective yes\n' >"$TEMPER_TMP/custom.snip"
  export TEMPER_SSH_CUSTOM_SRC="$TEMPER_TMP/custom.snip"
  d="$TEMPER_STATE_DIR/backups/s6"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_SSH_CUSTOM_SRC
  [ "$status" -ne 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
}

@test "ssh TUNNEL tun mode in vpn-tunnel writes ip_forward, elsewhere not" {
  _setup_ssh TUNNEL
  export TEMPER_TUNNEL_MODE=tun
  export TEMPER_PROFILE=vpn-tunnel
  d="$TEMPER_STATE_DIR/backups/s9"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_TUNNEL_MODE TEMPER_PROFILE
  [ "$status" -eq 0 ]
  grep -q "^net.ipv4.ip_forward=1" "$TEMPER_SYSROOT/etc/sysctl.d/00-temper-tun.conf"
}

@test "ssh TUNNEL outside vpn-tunnel writes no forwarding knobs" {
  _setup_ssh TUNNEL
  export TEMPER_TUNNEL_MODE=tun
  export TEMPER_PROFILE=generic
  d="$TEMPER_STATE_DIR/backups/s10"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_TUNNEL_MODE TEMPER_PROFILE
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/sysctl.d/00-temper-tun.conf" ]
}

@test "ssh port change writes a socket override" {
  _setup_ssh ADMIN
  export TEMPER_SSH_PORT=2222
  d="$TEMPER_STATE_DIR/backups/s7"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_SSH_PORT
  [ "$status" -eq 0 ]
  grep -qx "Port 22" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  grep -qx "Port 2222" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  grep -q "ListenStream=2222" "$TEMPER_SYSROOT/etc/systemd/system/ssh.socket.d/00-temper.conf"
}

@test "ssh fails when the new port never listens (injection)" {
  _setup_ssh ADMIN
  export TEMPER_SSH_PORT=2222
  export TEMPER_STUB_SS_RC=1
  d="$TEMPER_STATE_DIR/backups/s8"
  mkdir -p "$d"
  run ssh_apply "$d"
  unset TEMPER_SSH_PORT TEMPER_STUB_SS_RC
  [ "$status" -ne 0 ]
  [[ "$output" == *"not listening"* ]]
}

@test "ssh-close-port removes 22 only when 2222 listens" {
  _setup_ssh ADMIN
  export TEMPER_SSH_PORT=2222
  d="$TEMPER_STATE_DIR/backups/s7"
  mkdir -p "$d"
  ssh_apply "$d" >/dev/null
  unset TEMPER_SSH_PORT
  run ssh_close_port 22
  [ "$status" -eq 0 ]
  run grep -qx "Port 22" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  [ "$status" -ne 0 ]
  grep -qx "Port 2222" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
}

@test "ssh-close-port refuses when nothing listens as fallback" {
  _setup_ssh ADMIN
  export TEMPER_SSH_PORT=2222
  d="$TEMPER_STATE_DIR/backups/s7b"
  mkdir -p "$d"
  ssh_apply "$d" >/dev/null
  unset TEMPER_SSH_PORT
  export TEMPER_STUB_SS_RC=1
  run ssh_close_port 22
  unset TEMPER_STUB_SS_RC
  [ "$status" -ne 0 ]
  grep -qx "Port 22" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
}

@test "ssh-close-port refuses the last remaining port" {
  _setup_ssh ADMIN
  d="$TEMPER_STATE_DIR/backups/s7c"
  mkdir -p "$d"
  ssh_apply "$d" >/dev/null
  run ssh_close_port 22
  [ "$status" -ne 0 ]
  [[ "$output" == *"no ssh port"* ]]
}

@test "crash after write still reverts via the armed guard" {
  _setup_ssh ADMIN
  export TEMPER_GUARD_BACKEND=systemd
  export TEMPER_CRASH_AFTER_WRITE=1
  d="$TEMPER_STATE_DIR/backups/crash1"
  mkdir -p "$d"
  printf '# operator baseline\nPort 22\n' >"$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  # TEST/NO_GUARD off so the real guard path arms (systemd stubbed, no timer).
  run env -u TEMPER_TEST -u TEMPER_NO_GUARD \
    bash -c 'source "$1/lib/modules.sh"; module_load ssh; ssh_apply "$2"' bash "$TEMPER_ROOT" "$d"
  [ "$status" -ne 0 ]
  # The write happened (process died right after it)...
  grep -q "temper ADMIN" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  # ...and the armed guard's own revert script restores the original.
  [ -x "$TEMPER_STATE_DIR/guard/revert-crash1.sh" ]
  bash "$TEMPER_STATE_DIR/guard/revert-crash1.sh"
  grep -q "operator baseline" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  run grep -q "temper ADMIN" "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  [ "$status" -ne 0 ]
}
