#!/usr/bin/env bats
# Registry mirrors: tool-gated, apply only when the tool is installed.
# shellcheck shell=bash

load bats_helper

_setup_reg() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
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

@test "docker mirror writes only when daemon.json is absent" {
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
  run docker_mirror_apply "$d"
  unset SRV_TUNE_DOCKER_BIN
  [ "$status" -eq 0 ]
  grep -q "registry-mirrors" "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  run docker_mirror_verify
  [ "$status" -eq 0 ]
  # Existing daemon.json is never overwritten.
  printf '{"debug": true}\n' >"$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
  run docker_mirror_apply "$d"
  [ "$status" -eq 2 ]
  grep -q '"debug"' "$SRV_TUNE_SYSROOT/etc/docker/daemon.json"
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
