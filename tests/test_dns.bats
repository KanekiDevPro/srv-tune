#!/usr/bin/env bats
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
