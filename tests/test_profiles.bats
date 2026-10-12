#!/usr/bin/env bats
# P4: profiles, dangerous-module gating, interactive paths, i18n parity.
# shellcheck shell=bash

load bats_helper

_setup_p4() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  export OS_RELEASE_FILE="$SRV_TUNE_TMP/os-release"
  printf 'ID=ubuntu\nVERSION_ID=24.04\n' >"$SRV_TUNE_TMP/os-release"
  mkdir -p "$SRV_TUNE_TMP/proc/sys/fs" "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  printf 'MemTotal:        8192000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf '1048576\n' >"$SRV_TUNE_TMP/proc/sys/fs/nr_open"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
}

@test "every profile resolves to a module list" {
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  for p in generic web database docker vpn-tunnel low-ram custom; do
    run profile_modules "$p"
    [ "$status" -eq 0 ]
  done
}

@test "vpn-tunnel without --with-ssh skips ssh, applies the rest" {
  _setup_p4
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile vpn-tunnel --only limits,ssh --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-ssh"* ]]
  [ -f "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
}

@test "firewall needs --with-firewall even when requested" {
  _setup_p4
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only firewall --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-firewall"* ]]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/nftables.d/00-srv-tune.nft" ]
}

@test "typed phrase applies ssh, wrong phrase aborts cleanly" {
  _setup_p4
  export SRV_TUNE_SSH_MODE=ADMIN SRV_TUNE_SSH_USER=testuser
  export SRV_TUNE_TEST_USER_HOME="$SRV_TUNE_TMP/home/testuser"
  export SRV_TUNE_NO_GUARD=1
  mkdir -p "$SRV_TUNE_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$SRV_TUNE_TEST_USER_HOME/.ssh"
  chmod 600 "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$SRV_TUNE_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/sshd"
  export SRV_TUNE_SSHD_BIN="$SRV_TUNE_TMP/stubbin/sshd"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only ssh --with-ssh <<< $'\nSSH-YES\n'
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
  rm -f "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only ssh --with-ssh <<< $'\nnope\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"aborted"* ]]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
}

@test "non-interactive --with-ssh --yes needs no typing" {
  _setup_p4
  export SRV_TUNE_SSH_MODE=ADMIN SRV_TUNE_SSH_USER=testuser
  export SRV_TUNE_TEST_USER_HOME="$SRV_TUNE_TMP/home/testuser"
  export SRV_TUNE_NO_GUARD=1
  mkdir -p "$SRV_TUNE_TEST_USER_HOME/.ssh"
  printf 'ssh-ed25519 AAAAvalidkey testuser@host\n' >"$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  chmod 700 "$SRV_TUNE_TEST_USER_HOME/.ssh"
  chmod 600 "$SRV_TUNE_TEST_USER_HOME/.ssh/authorized_keys"
  cat >"$SRV_TUNE_TMP/stubbin/sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/sshd"
  export SRV_TUNE_SSHD_BIN="$SRV_TUNE_TMP/stubbin/sshd"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile generic --only ssh --with-ssh --yes
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d/00-srv-tune.conf" ]
}

@test "interactive profile default applies without --profile" {
  _setup_p4
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --only limits <<< $'\n'
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
}

@test "custom --config applies its modules, rejects unknown ones" {
  _setup_p4
  printf 'modules="limits"\n' >"$SRV_TUNE_TMP/good.conf"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile custom --config "$SRV_TUNE_TMP/good.conf" --yes
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/security/limits.d/00-srv-tune.conf" ]
  printf 'modules="nope"\n' >"$SRV_TUNE_TMP/bad.conf"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile custom --config "$SRV_TUNE_TMP/bad.conf" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown module"* ]]
  printf 'modules="limits"\nEVIL_KEY=1\n' >"$SRV_TUNE_TMP/evil.conf"
  run env SRV_TUNE_TEST=1 bash "$SRV_TUNE_ROOT/optimizer.sh" apply --profile custom --config "$SRV_TUNE_TMP/evil.conf" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported key"* ]]
}

@test "i18n keys match between en and fa" {
  en_keys="$(grep -E '^    [a-z_]+\)' "$SRV_TUNE_ROOT/lib/i18n/en.sh" | sed -E 's/^ +([a-z_]+)\).*/\1/' | sort)"
  fa_keys="$(grep -E '^    [a-z_]+\)' "$SRV_TUNE_ROOT/lib/i18n/fa.sh" | sed -E 's/^ +([a-z_]+)\).*/\1/' | sort)"
  [ "$en_keys" = "$fa_keys" ]
  [ -n "$en_keys" ]
}

@test "explain covers firewall and fail2ban" {
  run bash "$SRV_TUNE_ROOT/optimizer.sh" explain firewall
  [ "$status" -eq 0 ]
  [[ "$output" != *"not implemented"* ]]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" explain fail2ban
  [ "$status" -eq 0 ]
  [[ "$output" != *"not implemented"* ]]
}
