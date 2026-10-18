#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# completion + man page: registered function, real suggestions, installed
# artifacts, renderable man source.
# shellcheck shell=bash

load bats_helper

@test "bash completion registers srv-tune" {
  run bash -c 'source "$1/completion/srv-tune.bash" && complete -p srv-tune' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_srv_tune"* ]]
}

@test "bash completion suggests commands and flags" {
  run bash -c 'source "$1/completion/srv-tune.bash"; COMP_WORDS=(srv-tune ""); COMP_CWORD=1; _srv_tune; printf "%s\n" "${COMPREPLY[@]}"' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan"* ]]
  [[ "$output" == *"rollback"* ]]
  run bash -c 'source "$1/completion/srv-tune.bash"; COMP_WORDS=(srv-tune --pro); COMP_CWORD=1; _srv_tune; printf "%s\n" "${COMPREPLY[@]}"' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--profile"* ]]
}

@test "man page names the tool and its newest flags" {
  [ -f "$SRV_TUNE_ROOT/docs/srv-tune.1" ]
  run grep -q '^\.TH SRV-TUNE' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'dns.*extra' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'with.*registry' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'with.*dot' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'health' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'diff.*BASELINE' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'repair' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q "srv-tune $(cat "$SRV_TUNE_ROOT/VERSION")" "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  if ! command -v groff >/dev/null 2>&1; then
    skip "groff missing on this host; covered where man tooling exists"
  fi
  run groff -man -Tascii "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
}

@test "tunnel UI is documented, secured, and completable" {
  run grep -q -- 'TUNNEL UI' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$SRV_TUNE_ROOT/docs/srv-tune.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$SRV_TUNE_ROOT/README.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$SRV_TUNE_ROOT/README.fa.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel web panel' "$SRV_TUNE_ROOT/SECURITY.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel UI' "$SRV_TUNE_ROOT/docs/VERIFICATION-DEBT.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel' "$SRV_TUNE_ROOT/CHANGELOG.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel UI' "$SRV_TUNE_ROOT/docs/TESTING-VM.md"
  [ "$status" -eq 0 ]
  run bash -c 'source "$1/completion/srv-tune.bash"; COMP_WORDS=(srv-tune ""); COMP_CWORD=1; _srv_tune; printf "%s\n" "${COMPREPLY[@]}"' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tunnel"* ]]
  run bash -c 'source "$1/completion/srv-tune.bash"; COMP_WORDS=(srv-tune tunnel ""); COMP_CWORD=2; _srv_tune; printf "%s\n" "${COMPREPLY[@]}"' bash "$SRV_TUNE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"web"* ]]
  [[ "$output" == *"keys"* ]]
}

@test "install.sh ships completion and man page" {
  run bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix6" --yes
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_TMP/prefix6/share/srv-tune/completion/srv-tune.bash" ]
  [ -f "$SRV_TUNE_TMP/prefix6/share/man/man1/srv-tune.1" ]
}
