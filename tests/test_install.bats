#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# installer/update/uninstall: sandboxed prefix, checksum gates, no-apply rule.
# shellcheck shell=bash

load bats_helper

_file_url_works() {
  printf 'x' >"$TEMPER_TMP/probe.txt"
  curl -fsSL --max-time 10 "file://$TEMPER_TMP/probe.txt" >/dev/null 2>&1
}

@test "install.sh installs to a prefix and writes a manifest" {
  run bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix" --yes
  [ "$status" -eq 0 ]
  [ -x "$TEMPER_TMP/prefix/share/temper/optimizer.sh" ]
  [ -f "$TEMPER_TMP/prefix/share/temper/.install-manifest" ]
  # MSYS without symlink rights falls back to a copy: accept either link or file.
  [ -L "$TEMPER_TMP/prefix/bin/temper" ] || [ -f "$TEMPER_TMP/prefix/bin/temper" ]
  run bash "$TEMPER_TMP/prefix/bin/temper" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"temper"* ]]
}

@test "install.sh refuses piped stdin without --yes" {
  run bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix2" </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"Read the script first"* ]] || [[ "$output" == *"read the script"* ]] || [[ "$output" == *"not a terminal"* ]]
}

@test "install.sh refuses an apply action" {
  run bash "$TEMPER_ROOT/install.sh" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"never applies"* ]]
}

@test "install.sh --tag verifies the checksum (stubbed base)" {
  if ! _file_url_works; then
    skip "host curl cannot fetch file:// URLs; covered on Linux CI"
  fi
  base="$TEMPER_TMP/rel"
  mkdir -p "$base/v9.9.9" "$TEMPER_TMP/pkg/temper-v9.9.9"
  cp "$TEMPER_ROOT/optimizer.sh" "$TEMPER_ROOT/VERSION" "$TEMPER_TMP/pkg/temper-v9.9.9/"
  printf 'MIT\n' >"$TEMPER_TMP/pkg/temper-v9.9.9/LICENSE"
  tar czf "$base/v9.9.9/temper-v9.9.9.tar.gz" -C "$TEMPER_TMP/pkg" temper-v9.9.9
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$base/v9.9.9/temper-v9.9.9.tar.gz" | awk '{print $1}')"
  else
    skip "sha256sum missing on this host"
  fi
  run env TEMPER_RELEASE_BASE="file://$base" bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix3" --yes --tag v9.9.9 --sha256 "$sum"
  [ "$status" -eq 0 ]
  [ -x "$TEMPER_TMP/prefix3/share/temper/optimizer.sh" ]
  run env TEMPER_RELEASE_BASE="file://$base" bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix4" --yes --tag v9.9.9 --sha256 deadbeef
  [ "$status" -ne 0 ]
  [[ "$output" == *"mismatch"* ]]
}

@test "update verifies checksums and uninstall removes program files" {
  if ! _file_url_works; then
    skip "host curl cannot fetch file:// URLs; covered on Linux CI"
  fi
  base="$TEMPER_TMP/rel2"
  mkdir -p "$base/v9.9.8" "$TEMPER_TMP/pkg2/temper-v9.9.8"
  cp "$TEMPER_ROOT/optimizer.sh" "$TEMPER_TMP/pkg2/temper-v9.9.8/"
  printf '9.9.8\n' >"$TEMPER_TMP/pkg2/temper-v9.9.8/VERSION"
  tar czf "$base/v9.9.8/temper-v9.9.8.tar.gz" -C "$TEMPER_TMP/pkg2" temper-v9.9.8
  if ! command -v sha256sum >/dev/null 2>&1; then
    skip "sha256sum missing on this host"
  fi
  sum="$(sha256sum "$base/v9.9.8/temper-v9.9.8.tar.gz" | awk '{print $1}')"
  printf '%s  temper-v9.9.8.tar.gz\n' "$sum" >"$base/v9.9.8/sha256sums.txt"
  printf 'v9.9.8\n' >"$TEMPER_TMP/apitag"
  run env TEMPER_UPDATE_API_STUB="$TEMPER_TMP/apitag" TEMPER_RELEASE_BASE="file://$base" \
    bash -c 'source "$1"; self_update' bash "$TEMPER_ROOT/lib/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified v9.9.8"* ]]
  run bash "$TEMPER_ROOT/install.sh" --prefix "$TEMPER_TMP/prefix5" --yes
  [ "$status" -eq 0 ]
  run env TEMPER_PREFIX="$TEMPER_TMP/prefix5" bash "$TEMPER_ROOT/optimizer.sh" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_TMP/prefix5/share/temper" ]
  [ ! -e "$TEMPER_TMP/prefix5/bin/temper" ]
}
