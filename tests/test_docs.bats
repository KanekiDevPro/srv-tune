#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# completion + man page: registered function, real suggestions, installed
# artifacts, renderable man source.
# shellcheck shell=bash

load bats_helper

@test "bash completion registers temper" {
  run bash -c 'source "$1/completion/temper.bash" && complete -p temper' bash "$TEMPER_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_temper"* ]]
}

@test "bash completion suggests commands and flags" {
  run bash -c 'source "$1/completion/temper.bash"; COMP_WORDS=(temper ""); COMP_CWORD=1; _temper; printf "%s\n" "${COMPREPLY[@]}"' bash "$TEMPER_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan"* ]]
  [[ "$output" == *"rollback"* ]]
  run bash -c 'source "$1/completion/temper.bash"; COMP_WORDS=(temper --pro); COMP_CWORD=1; _temper; printf "%s\n" "${COMPREPLY[@]}"' bash "$TEMPER_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--profile"* ]]
}

@test "man page names the tool and its newest flags" {
  [ -f "$TEMPER_ROOT/docs/temper.1" ]
  run grep -q '^\.TH TEMPER' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'dns.*extra' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'with.*registry' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'with.*dot' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'health' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'diff.*BASELINE' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'repair' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q "temper $(cat "$TEMPER_ROOT/VERSION")" "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  if ! command -v groff >/dev/null 2>&1; then
    skip "groff missing on this host; covered where man tooling exists"
  fi
  run groff -man -Tascii "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
}

@test "tunnel UI is documented, secured, and completable" {
  run grep -q -- 'TUNNEL UI' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$TEMPER_ROOT/docs/temper.1"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$TEMPER_ROOT/README.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel web' "$TEMPER_ROOT/README.fa.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel web panel' "$TEMPER_ROOT/SECURITY.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'tunnel UI' "$TEMPER_ROOT/docs/VERIFICATION-DEBT.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel' "$TEMPER_ROOT/CHANGELOG.md"
  [ "$status" -eq 0 ]
  run grep -q -- 'Tunnel UI' "$TEMPER_ROOT/docs/TESTING-VM.md"
  [ "$status" -eq 0 ]
  run bash -c 'source "$1/completion/temper.bash"; COMP_WORDS=(temper ""); COMP_CWORD=1; _temper; printf "%s\n" "${COMPREPLY[@]}"' bash "$TEMPER_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tunnel"* ]]
  run bash -c 'source "$1/completion/temper.bash"; COMP_WORDS=(temper tunnel ""); COMP_CWORD=2; _temper; printf "%s\n" "${COMPREPLY[@]}"' bash "$TEMPER_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"web"* ]]
  [[ "$output" == *"keys"* ]]
}

@test "install.sh ships completion and man page" {
  run bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix6" --yes
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_TMP/prefix6/share/temper/completion/temper.bash" ]
  [ -f "$TEMPER_TMP/prefix6/share/man/man1/temper.1" ]
}
