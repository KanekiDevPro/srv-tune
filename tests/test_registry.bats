#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Registry mirrors: tool-gated, HTTPS-only, merged configs, reachability
# rollback, --with-registry opt-in. Never in default profiles.
# shellcheck shell=bash

load bats_helper

_setup_reg() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  cat >"$SRV_TUNE_TMP/stubbin/curl" <<'EOF'
#!/usr/bin/env bash
exit ${SRV_TUNE_STUB_CURL_RC:-0}
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/curl"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # Lists are all verified=pending: the test-only override unlocks them.
  export SRV_TUNE_ALLOW_UNVERIFIED=1
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
}

_mktool() {
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SRV_TUNE_TMP/stubbin/$1"
  chmod +x "$SRV_TUNE_TMP/stubbin/$1"
}

@test "pip mirror applies only when pip exists" {
  _setup_reg
  module_load pip_mirror
  d="$SRV_TUNE_STATE_DIR/backups/p1"
  mkdir -p "$d"
  export SRV_TUNE_PIP_BIN=none
  run pip_mirror_apply "$d"
  unset SRV_TUNE_PIP_BIN
  [ "$status" -eq 2 ]
  _mktool pip
  export SRV_TUNE_PIP_BIN="$SRV_TUNE_TMP/stubbin/pip"
  run pip_mirror_apply "$d"
  unset SRV_TUNE_PIP_BIN
  [ "$status" -eq 0 ]
  grep -q "index-url" "$SRV_TUNE_SYSROOT/etc/pip.conf"
  run pip_mirror_verify
  [ "$status" -eq 0 ]
}

@test "npm mirror applies only when npm exists" {
  _setup_reg
  module_load npm_mirror
  d="$SRV_TUNE_STATE_DIR/backups/n1"
  mkdir -p "$d"
  export SRV_TUNE_NPM_BIN=none
  run npm_mirror_apply "$d"
  unset SRV_TUNE_NPM_BIN
  [ "$status" -eq 2 ]
  _mktool npm
  export SRV_TUNE_NPM_BIN="$SRV_TUNE_TMP/stubbin/npm"
  run npm_mirror_apply "$d"
  unset SRV_TUNE_NPM_BIN
  [ "$status" -eq 0 ]
  grep -q "^registry=" "$SRV_TUNE_SYSROOT/etc/npmrc"
  run npm_mirror_verify
  [ "$status" -eq 0 ]
}

@test "docker mirror merges, preserving existing keys" {
  _setup_reg
  module_load docker_mirror
  d="$SRV_TUNE_STATE_DIR/backups/k1"
  mkdir -p "$d"
  export SRV_TUNE_DOCKER_BIN=none
  run docker_mirror_apply "$d"
  unset SRV_TUNE_DOCKER_BIN
  [ "$status" -eq 2 ]
  _mktool docker
  export SRV_TUNE_DOCKER_BIN="$SRV_TUNE_TMP/stubbin/docker"
  # Docker list holds only the official-default origin: reach it explicitly.
  export SRV_TUNE_MIRROR_URL="https://docker-mirror.example.com/"
  run docker_mirror_apply "$d"
  unset SRV_TUNE_DOCKER_BIN
  [ "$status" -eq 0 ]
  grep -q "registry-mirrors" "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  run docker_mirror_verify
  unset SRV_TUNE_MIRROR_URL
  [ "$status" -eq 0 ]
  if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    skip "no JSON merge tool on this host; covered on Linux CI"
  fi
  # Pre-existing keys survive apply AND rollback.
  printf '{"debug": true, "log-level": "warn"}\n' >"$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  export SRV_TUNE_DOCKER_BIN="$SRV_TUNE_TMP/stubbin/docker"
  export SRV_TUNE_MIRROR_URL="https://docker-mirror.example.com/"
  run docker_mirror_apply "$d"
  unset SRV_TUNE_DOCKER_BIN SRV_TUNE_MIRROR_URL
  [ "$status" -eq 0 ]
  grep -q '"debug"' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  grep -q '"log-level"' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  grep -q 'registry-mirrors' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  run rollback_id "$(basename "$d")"
  [ "$status" -eq 0 ]
  grep -q '"debug"' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  run grep -q 'registry-mirrors' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  [ "$status" -ne 0 ]
}

@test "docker mirror aborts on invalid existing JSON" {
  _setup_reg
  module_load docker_mirror
  if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    skip "no JSON tool on this host"
  fi
  _mktool docker
  export SRV_TUNE_DOCKER_BIN="$SRV_TUNE_TMP/stubbin/docker"
  export SRV_TUNE_MIRROR_URL="https://docker-mirror.example.com/"
  mkdir -p "$SRV_TUNE_SYSROOT/etc/docker"
  printf '{oops\n' >"$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  d="$SRV_TUNE_STATE_DIR/backups/k2"
  mkdir -p "$d"
  run docker_mirror_apply "$d"
  unset SRV_TUNE_DOCKER_BIN SRV_TUNE_MIRROR_URL
  [ "$status" -ne 0 ]
  grep -q '{oops' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
}

@test "http mirror URLs are refused" {
  _setup_reg
  module_load pip_mirror
  export SRV_TUNE_MIRROR_URL="http://evil.example.com/simple/"
  d="$SRV_TUNE_STATE_DIR/backups/p2"
  mkdir -p "$d"
  _mktool pip
  export SRV_TUNE_PIP_BIN="$SRV_TUNE_TMP/stubbin/pip"
  run pip_mirror_apply "$d"
  unset SRV_TUNE_MIRROR_URL SRV_TUNE_PIP_BIN
  [ "$status" -ne 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/pip.conf" ]
}

@test "docker mirror refuses when no JSON tool and changes nothing" {
  _setup_reg
  module_load docker_mirror
  _mktool docker
  export SRV_TUNE_DOCKER_BIN="$SRV_TUNE_TMP/stubbin/docker"
  export SRV_TUNE_JSON_TOOL=none
  export SRV_TUNE_MIRROR_URL="https://docker-mirror.example.com/"
  mkdir -p "$SRV_TUNE_SYSROOT/etc/docker"
  printf '{"debug": true}\n' >"$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  d="$SRV_TUNE_STATE_DIR/backups/k3"
  mkdir -p "$d"
  run docker_mirror_apply "$d"
  unset SRV_TUNE_JSON_TOOL SRV_TUNE_DOCKER_BIN SRV_TUNE_MIRROR_URL
  [ "$status" -ne 0 ]
  [[ "$output" == *"python3 or jq"* ]]
  grep -q '"debug"' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  run grep -q 'registry-mirrors' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  [ "$status" -ne 0 ]
}

@test "registry data lists use https only" {
  run awk '!/^#/ && NF>0 && $1 !~ /^https:\/\// {print FILENAME": "$0; bad=1} END {exit bad}' "$SRV_TUNE_ROOT/data/mirrors-pip.list" "$SRV_TUNE_ROOT/data/mirrors-npm.list" "$SRV_TUNE_ROOT/data/mirrors-docker.list"
  [ "$status" -eq 0 ]
}

@test "official-default origins are never auto-selected" {
  _setup_reg
  module_load pip_mirror
  # pypi.org is tier official-default: the auto-pick must skip it.
  run pip_mirror_url
  [ "$status" -eq 0 ]
  [[ "$output" == *"runflare"* ]]
  [[ "$output" != *"pypi.org"* ]]
  module_load npm_mirror
  run npm_mirror_url
  [ "$status" -eq 0 ]
  [[ "$output" == *"yarnpkg"* ]]
  [[ "$output" != *"registry.npmjs.org"* ]]
  # Docker lists only the origin: auto-pick finds nothing (reset needs
  # an explicit --mirror URL).
  module_load docker_mirror
  run docker_mirror_url
  [ "$status" -ne 0 ]
}

@test "--mirror URL is honored when https" {
  _setup_reg
  module_load npm_mirror
  _mktool npm
  export SRV_TUNE_NPM_BIN="$SRV_TUNE_TMP/stubbin/npm"
  export SRV_TUNE_MIRROR_URL="https://custom.example.com/"
  d="$SRV_TUNE_STATE_DIR/backups/n2"
  mkdir -p "$d"
  run npm_mirror_apply "$d"
  unset SRV_TUNE_MIRROR_URL SRV_TUNE_NPM_BIN
  [ "$status" -eq 0 ]
  grep -q "custom.example.com" "$SRV_TUNE_SYSROOT/etc/npmrc"
}

@test "unreachable mirror triggers rollback" {
  _setup_reg
  module_load pip_mirror
  _mktool pip
  export SRV_TUNE_PIP_BIN="$SRV_TUNE_TMP/stubbin/pip"
  export SRV_TUNE_STUB_CURL_RC=7
  d="$SRV_TUNE_STATE_DIR/backups/p3"
  mkdir -p "$d"
  run pip_mirror_apply "$d"
  [ "$status" -eq 0 ]
  run pip_mirror_verify
  unset SRV_TUNE_STUB_CURL_RC SRV_TUNE_PIP_BIN
  [ "$status" -ne 0 ]
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/rollback.sh"
  run rollback_id "p3"
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/pip.conf" ]
}

@test "registry modules dry-run writes nothing" {
  _setup_reg
  _mktool pip
  export SRV_TUNE_PIP_BIN="$SRV_TUNE_TMP/stubbin/pip"
  module_load pip_mirror
  d="$SRV_TUNE_STATE_DIR/backups/p9"
  mkdir -p "$d"
  export SRV_TUNE_DRY_RUN=1
  run pip_mirror_apply "$d"
  unset SRV_TUNE_DRY_RUN SRV_TUNE_PIP_BIN
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/pip.conf" ]
}

@test "registry modules need --with-registry and are never default" {
  _setup_reg
  # No shipped profile may list registry modules (One-Enter safety).
  run bash -c 'grep -rh "^modules=" "$1"/profiles/*.conf' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"pip_mirror"* ]]
  [[ "$output" != *"npm_mirror"* ]]
  [[ "$output" != *"docker_mirror"* ]]
  # Runner refuses them without the flag, runs with flag + typed phrase.
  export SRV_TUNE_SSH_MODE=ADMIN
  _mktool pip
  export SRV_TUNE_PIP_BIN="$SRV_TUNE_TMP/stubbin/pip"
  run env SRV_TUNE_TEST=1 bash -c 'source "$1/lib/modules.sh"; run_apply custom pip_mirror' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-registry"* ]]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/pip.conf" ]
}
