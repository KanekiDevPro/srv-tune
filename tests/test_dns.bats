#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# dns module: benchmark, sandboxed apply, verify, failure injection.
# shellcheck shell=bash

load bats_helper

_setup_dns() {
  # $1 = dig mode (ok|fail), $2 = backend (resolv.conf|resolved)
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_DNS_PROBE=probe.invalid
  export SRV_TUNE_DNS_VERIFY_HOST=probe.invalid
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  printf 'nameserver 9.9.9.9\n' >"$SRV_TUNE_SYSROOT/etc/resolv.conf"
  cat >"$SRV_TUNE_TMP/stubbin/dig" <<EOF
#!/usr/bin/env bash
if [[ "$1" == "fail" ]]; then exit 9; fi
printf ';; ANSWER SECTION:\nprobe.invalid. 300 IN A 192.0.2.1\n;; Query time: 7 msec\n'
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/dig"
  cat >"$SRV_TUNE_TMP/stubbin/getent" <<'EOF'
#!/usr/bin/env bash
exit ${SRV_TUNE_STUB_GETENT_RC:-0}
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/getent"
  cat >"$SRV_TUNE_TMP/stubbin/systemctl" <<EOF
#!/usr/bin/env bash
exit 3
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/systemctl"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # Lists are all verified=pending: the test-only override unlocks them.
  export SRV_TUNE_ALLOW_UNVERIFIED=1
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load dns
}

@test "dns benchmark ranks candidates and prints contacted hosts" {
  _setup_dns ok resolv.conf
  run dns_benchmark
  [ "$status" -eq 0 ]
  [[ "$output" == *"contacting resolvers:"* ]]
  [[ "$output" == *"1.1.1.1"* ]]
}

@test "dns apply writes resolv.conf and verify passes" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_STUB_GETENT_RC=0
  d="$SRV_TUNE_STATE_DIR/backups/d1"
  mkdir -p "$d"
  run dns_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "^nameserver 1.1.1.1" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
  run dns_verify
  [ "$status" -eq 0 ]
}

@test "dns failure injection: broken resolution rolls back" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_STUB_GETENT_RC=0
  d="$SRV_TUNE_STATE_DIR/backups/d2"
  mkdir -p "$d"
  dns_apply "$d"
  grep -q "^nameserver 1.1.1.1" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
  # Resolution breaks after apply: verify must fail, rollback restores.
  export SRV_TUNE_STUB_GETENT_RC=2
  run dns_verify
  [ "$status" -ne 0 ]
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  run rollback_id "d2"
  [ "$status" -eq 0 ]
  grep -q "^nameserver 9.9.9.9" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
}

@test "dns refuses when every resolver fails" {
  _setup_dns fail resolv.conf
  d="$SRV_TUNE_STATE_DIR/backups/d3"
  mkdir -p "$d"
  run dns_apply "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"every candidate resolver failed"* ]]
  grep -q "^nameserver 9.9.9.9" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
}

@test "dns falls back to drill when dig is missing" {
  _setup_dns ok resolv.conf
  cat >"$SRV_TUNE_TMP/stubbin/drill" <<'EOF'
#!/usr/bin/env bash
printf ';; ANSWER SECTION:\nprobe.invalid. 300 IN A 192.0.2.1\n;; Query time: 9 msec\n'
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/drill"
  export SRV_TUNE_DNS_TOOL=drill
  run dns_tool
  [ "$status" -eq 0 ]
  [[ "$output" == "drill" ]]
  run dns_benchmark
  [ "$status" -eq 0 ]
  [[ "$output" == *"contacting resolvers:"* ]]
  unset SRV_TUNE_DNS_TOOL
}

@test "dns refuses cloud-init managed resolv.conf" {
  _setup_dns ok resolv.conf
  mkdir -p "$SRV_TUNE_SYSROOT/etc/cloud"
  printf 'manage-resolv-conf: true\n' >"$SRV_TUNE_SYSROOT/etc/cloud/cloud.cfg"
  d="$SRV_TUNE_STATE_DIR/backups/d4"
  mkdir -p "$d"
  run dns_apply "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cloud-init"* ]]
}

@test "dns auto pool is tier default only" {
  _setup_dns ok resolv.conf
  run dns_candidates
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.1.1.1"* ]]
  [[ "$output" == *"8.8.8.8"* ]]
  [[ "$output" == *"9.9.9.9"* ]]
  [[ "$output" != *"77.88.8.8"* ]]
  [[ "$output" != *"178.22.122.100"* ]]
  [[ "$output" != *"185.51.200.2"* ]]
}

@test "dns extras join via --dns-extra after typed disclosure" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_DNS_EXTRA=shecan
  export SRV_TUNE_ASSUME_YES=1
  run dns_candidates
  [ "$status" -eq 0 ]
  [[ "$output" == *"178.22.122.100"* ]]
  d="$SRV_TUNE_STATE_DIR/backups/d5"
  mkdir -p "$d"
  export SRV_TUNE_STUB_GETENT_RC=0
  run dns_apply "$d"
  unset SRV_TUNE_DNS_EXTRA SRV_TUNE_ASSUME_YES SRV_TUNE_STUB_GETENT_RC
  [ "$status" -eq 0 ]
  [[ "$output" == *"RISK extra resolvers"* ]]
}

@test "dns extras abort without typed disclosure on non-tty" {
  _setup_dns ok resolv.conf
  unset SRV_TUNE_ASSUME_YES
  export SRV_TUNE_DNS_EXTRA=shecan
  d="$SRV_TUNE_STATE_DIR/backups/d6"
  mkdir -p "$d"
  run dns_apply "$d"
  unset SRV_TUNE_DNS_EXTRA
  [ "$status" -ne 0 ]
  grep -q "^nameserver 9.9.9.9" "$SRV_TUNE_SYSROOT/etc/resolv.conf"
}

@test "unknown --dns-extra ID fails loudly" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_DNS_EXTRA=bogus
  run dns_candidates
  unset SRV_TUNE_DNS_EXTRA
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown --dns-extra ID"* ]]
}

@test "dns recommend offers DoT only for reachable winners" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_DOT_PROBE=open
  run dns_recommend
  unset SRV_TUNE_DOT_PROBE
  [ "$status" -eq 0 ]
  [[ "$output" == *"853 reachable"* ]]
  [[ "$output" == *"stays off unless"* ]]
  export SRV_TUNE_DOT_PROBE=closed
  run dns_recommend
  unset SRV_TUNE_DOT_PROBE
  [ "$status" -eq 0 ]
  [[ "$output" == *"not offered"* ]]
  [[ "$output" != *"853 reachable"* ]]
}

@test "dns --with-dot enables DoT on the resolved backend" {
  _setup_dns ok resolv.conf
  mkdir -p "$SRV_TUNE_SYSROOT/run/systemd/resolve"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SRV_TUNE_TMP/stubbin/systemctl"
  chmod +x "$SRV_TUNE_TMP/stubbin/systemctl"
  export SRV_TUNE_WITH_DOT=1
  export SRV_TUNE_DOT_PROBE=open
  export SRV_TUNE_STUB_GETENT_RC=0
  d="$SRV_TUNE_STATE_DIR/backups/d7"
  mkdir -p "$d"
  run dns_apply "$d"
  unset SRV_TUNE_WITH_DOT SRV_TUNE_DOT_PROBE SRV_TUNE_STUB_GETENT_RC
  [ "$status" -eq 0 ]
  grep -q "^DNSOverTLS=yes" "$SRV_TUNE_SYSROOT/etc/systemd/resolved.conf.d/00-srv-tune.conf"
  run dns_verify
  [ "$status" -eq 0 ]
}

@test "dns --with-dot refuses an unreachable winner" {
  _setup_dns ok resolv.conf
  mkdir -p "$SRV_TUNE_SYSROOT/run/systemd/resolve"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SRV_TUNE_TMP/stubbin/systemctl"
  chmod +x "$SRV_TUNE_TMP/stubbin/systemctl"
  export SRV_TUNE_WITH_DOT=1
  export SRV_TUNE_DOT_PROBE=closed
  d="$SRV_TUNE_STATE_DIR/backups/d8"
  mkdir -p "$d"
  run dns_apply "$d"
  unset SRV_TUNE_WITH_DOT SRV_TUNE_DOT_PROBE
  [ "$status" -ne 0 ]
  [[ "$output" == *"853"* ]]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/systemd/resolved.conf.d/00-srv-tune.conf" ]
}

@test "dns --with-dot refuses a non-resolved backend" {
  _setup_dns ok resolv.conf
  export SRV_TUNE_WITH_DOT=1
  export SRV_TUNE_DOT_PROBE=open
  d="$SRV_TUNE_STATE_DIR/backups/d9"
  mkdir -p "$d"
  run dns_apply "$d"
  unset SRV_TUNE_WITH_DOT SRV_TUNE_DOT_PROBE
  [ "$status" -ne 0 ]
  [[ "$output" == *"systemd-resolved"* ]]
}

@test "dns netplan backend writes yaml" {
  _setup_dns ok resolv.conf
  mkdir -p "$SRV_TUNE_SYSROOT/etc/netplan"
  printf '# test netplan\nnetwork:\n  version: 2\n' >"$SRV_TUNE_SYSROOT/etc/netplan/99-test.yaml"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SRV_TUNE_TMP/stubbin/netplan"
  chmod +x "$SRV_TUNE_TMP/stubbin/netplan"
  export SRV_TUNE_STUB_GETENT_RC=0
  d="$SRV_TUNE_STATE_DIR/backups/d10"
  mkdir -p "$d"
  run dns_apply "$d"
  unset SRV_TUNE_STUB_GETENT_RC
  [ "$status" -eq 0 ]
  grep -q "1.1.1.1" "$SRV_TUNE_SYSROOT/etc/netplan/00-srv-tune.yaml"
  run dns_verify
  [ "$status" -eq 0 ]
}
