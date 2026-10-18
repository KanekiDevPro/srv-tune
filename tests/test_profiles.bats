#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# P4: profiles, dangerous-module gating, interactive paths, i18n parity.
# shellcheck shell=bash

load bats_helper

_setup_p4() {
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  export OS_RELEASE_FILE="$TEMPER_TMP/os-release"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$TEMPER_TMP/os-release"
  mkdir -p "$TEMPER_TMP/proc/sys/fs" "$TEMPER_TMP/stubbin" "$TEMPER_SYSROOT/etc"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf '1048576\n' >"$TEMPER_TMP/proc/sys/fs/nr_open"
  export PATH="$TEMPER_TMP/stubbin:$PATH"
}

@test "every profile resolves to a module list" {
  source "$TEMPER_ROOT/lib/modules.sh"
  for p in generic web database docker vpn-tunnel low-ram custom; do
    run profile_modules "$p"
    [ "$status" -eq 0 ]
  done
}

@test "vpn-tunnel without --with-ssh skips ssh, applies the rest" {
  _setup_p4
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile vpn-tunnel --only limits,ssh --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-ssh"* ]]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
  [ ! -e "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
}

@test "firewall needs --with-firewall even when requested" {
  _setup_p4
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only firewall --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-firewall"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/nftables.d/00-temper.nft" ]
}

@test "typed phrase applies ssh, wrong phrase aborts cleanly" {
  _setup_p4
  export TEMPER_SSH_MODE=ADMIN TEMPER_SSH_USER=testuser
  export TEMPER_TEST_USER_HOME="$TEMPER_TMP/home/testuser"
  export TEMPER_NO_GUARD=1
  export TEMPER_WITH_SSH=1
  mkdir -p "$TEMPER_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$TEMPER_TEST_USER_HOME/.ssh"
  chmod 600 "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$TEMPER_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEMPER_TMP/stubbin/sshd"
  export TEMPER_SSHD_BIN="$TEMPER_TMP/stubbin/sshd"
  # Typed consent is read from stdin even on non-tty (explicit beats default).
  run env TEMPER_TEST=1 bash -c 'source "$1/lib/modules.sh"; run_apply generic ssh' bash "$TEMPER_ROOT" <<<$'SSH-YES\n'
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
  rm -f "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf"
  run env TEMPER_TEST=1 bash -c 'source "$1/lib/modules.sh"; run_apply generic ssh' bash "$TEMPER_ROOT" <<<$'nope\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"aborted"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
}

@test "blanket confirm refuses on non-tty without --yes" {
  _setup_p4
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only limits <<<$'\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a terminal"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "non-interactive --with-ssh --yes needs no typing" {
  _setup_p4
  export TEMPER_SSH_MODE=ADMIN TEMPER_SSH_USER=testuser
  export TEMPER_TEST_USER_HOME="$TEMPER_TMP/home/testuser"
  export TEMPER_NO_GUARD=1
  mkdir -p "$TEMPER_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$TEMPER_TEST_USER_HOME/.ssh"
  chmod 600 "$TEMPER_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$TEMPER_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEMPER_TMP/stubbin/sshd"
  export TEMPER_SSHD_BIN="$TEMPER_TMP/stubbin/sshd"
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only ssh --with-ssh --yes
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/ssh/sshd_config.d/00-temper.conf" ]
}

@test "recommended profile applies without --profile when confirmed" {
  _setup_p4
  run env TEMPER_TEST=1 TEMPER_ASSUME_YES=1 bash "$TEMPER_ROOT/optimizer.sh" apply --only limits <<<$'\n'
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "non-tty without --yes never applies" {
  _setup_p4
  run env TEMPER_TEST=1 TEMPER_ASSUME_YES=0 bash "$TEMPER_ROOT/optimizer.sh" apply --profile generic --only limits <<<$'\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a terminal"* ]]
  [ ! -e "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
}

@test "custom --config applies its modules, rejects unknown ones" {
  _setup_p4
  printf 'modules="limits"\n' >"$TEMPER_TMP/good.conf"
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile custom --config "$TEMPER_TMP/good.conf" --yes
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/security/limits.d/00-temper.conf" ]
  printf 'modules="nope"\n' >"$TEMPER_TMP/bad.conf"
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile custom --config "$TEMPER_TMP/bad.conf" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown module"* ]]
  printf 'modules="limits"\nEVIL_KEY=1\n' >"$TEMPER_TMP/evil.conf"
  run env TEMPER_TEST=1 bash "$TEMPER_ROOT/optimizer.sh" apply --profile custom --config "$TEMPER_TMP/evil.conf" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported key"* ]]
}

@test "i18n keys match between en and fa" {
  en_keys="$(grep -E '^[[:space:]]*[a-z_]+\)' "$TEMPER_ROOT/lib/i18n/en.sh" | sed -E 's/^ *([a-z_]+)\).*/\1/' | sort)"
  fa_keys="$(grep -E '^[[:space:]]*[a-z_]+\)' "$TEMPER_ROOT/lib/i18n/fa.sh" | sed -E 's/^ *([a-z_]+)\).*/\1/' | sort)"
  [ "$en_keys" = "$fa_keys" ]
  [ -n "$en_keys" ]
}

@test "explain covers firewall and fail2ban" {
  run bash "$TEMPER_ROOT/optimizer.sh" explain firewall
  [ "$status" -eq 0 ]
  [[ "$output" != *"not implemented"* ]]
  run bash "$TEMPER_ROOT/optimizer.sh" explain fail2ban
  [ "$status" -eq 0 ]
  [[ "$output" != *"not implemented"* ]]
}
