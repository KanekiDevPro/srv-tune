#!/usr/bin/env bats
# mirror module: benchmark, URI swap in both apt formats, verify, injection.
# shellcheck shell=bash

load bats_helper

_setup_mirror() {
  # $1 = curl mode (ok|failall), $2 = apt rc (0|1)
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_OS_RELEASE="$SRV_TUNE_TMP/os-release"
  printf 'ID=debian\nVERSION_ID=13\n' >"$SRV_TUNE_TMP/os-release"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d"
  printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: stable\nComponents: main\n' \
    >"$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  printf 'deb http://deb.debian.org/debian stable main\n' >"$SRV_TUNE_SYSROOT/etc/apt/sources.list"
  cat >"$SRV_TUNE_TMP/stubbin/curl" <<EOF
#!/usr/bin/env bash
if [[ "$1" == "failall" ]]; then exit 28; fi
for a in "\$@"; do
  case "\$a" in
    *deb.debian.org*) exit 28 ;;
  esac
done
printf '0.042 200'
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/curl"
  cat >"$SRV_TUNE_TMP/stubbin/apt-get" <<EOF
#!/usr/bin/env bash
exit $2
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/apt-get"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load mirror
}

@test "mirror benchmark picks a working mirror and prints hosts" {
  _setup_mirror ok 0
  run mirror_benchmark
  [ "$status" -eq 0 ]
  [[ "$output" == *"contacting mirrors:"* ]]
}

@test "mirror apply swaps the URI and verifies" {
  _setup_mirror ok 0
  d="$SRV_TUNE_STATE_DIR/backups/m1"
  mkdir -p "$d"
  run mirror_apply "$d"
  [ "$status" -eq 0 ]
  run grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  [ "$status" -ne 0 ]
  grep -q "^URIs:" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  run grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list"
  [ "$status" -ne 0 ]
  run mirror_verify
  [ "$status" -eq 0 ]
}

@test "mirror failure injection: dead mirrors change nothing" {
  _setup_mirror failall 0
  d="$SRV_TUNE_STATE_DIR/backups/m2"
  mkdir -p "$d"
  run mirror_apply "$d"
  [ "$status" -ne 0 ]
  grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list"
}

@test "mirror failure injection: failed apt update rolls back" {
  _setup_mirror ok 1
  d="$SRV_TUNE_STATE_DIR/backups/m3"
  mkdir -p "$d"
  mirror_apply "$d"
  run grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  [ "$status" -ne 0 ]
  export SRV_TUNE_FORCE_LIVE_VERIFY=1
  run mirror_verify
  unset SRV_TUNE_FORCE_LIVE_VERIFY
  [ "$status" -ne 0 ]
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  run rollback_id "m3"
  [ "$status" -eq 0 ]
  grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
}

@test "mirror verify refuses trusted=yes and allow-insecure" {
  _setup_mirror ok 0
  printf 'Types: deb\nURIs: http://mirror.hetzner.com/debian\nSuites: stable\nComponents: main\nTrusted: yes\n' \
    >"$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  run mirror_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"trusted=yes"* ]]
  printf 'deb [trusted=yes] http://mirror.hetzner.com/debian stable main\n' \
    >"$SRV_TUNE_SYSROOT/etc/apt/sources.list"
  run mirror_verify
  [ "$status" -ne 0 ]
  printf 'deb http://mirror.hetzner.com/debian stable main\n' >"$SRV_TUNE_SYSROOT/etc/apt/sources.list"
  printf 'Types: deb\nURIs: http://mirror.hetzner.com/debian\nSuites: stable\nComponents: main\nAllow-Insecure: yes\n' \
    >"$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
  run mirror_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"allow-insecure"* ]]
}

@test "mirror recommend warns when no security suite exists" {
  _setup_mirror ok 0
  run mirror_suite_warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"no security suite"* ]]
}

@test "mirror dry-run writes nothing" {
  _setup_mirror ok 0
  d="$SRV_TUNE_STATE_DIR/backups/m9"
  mkdir -p "$d"
  export SRV_TUNE_DRY_RUN=1
  run mirror_apply "$d"
  unset SRV_TUNE_DRY_RUN
  [ "$status" -eq 0 ]
  grep -q "deb.debian.org" "$SRV_TUNE_SYSROOT/etc/apt/sources.list.d/debian.sources"
}
