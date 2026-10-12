#!/usr/bin/env bats
# installer/update/uninstall: sandboxed prefix, checksum gates, no-apply rule.
# shellcheck shell=bash

load bats_helper

_file_url_works() {
  printf 'x' >"$SRV_TUNE_TMP/probe.txt"
  curl -fsSL --max-time 10 "file://$SRV_TUNE_TMP/probe.txt" >/dev/null 2>&1
}

@test "install.sh installs to a prefix and writes a manifest" {
  run bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix" --yes
  [ "$status" -eq 0 ]
  [ -x "$SRV_TUNE_TMP/prefix/share/srv-tune/optimizer.sh" ]
  [ -f "$SRV_TUNE_TMP/prefix/share/srv-tune/.install-manifest" ]
  # MSYS without symlink rights falls back to a copy: accept either link or file.
  [ -L "$SRV_TUNE_TMP/prefix/bin/srv-tune" ] || [ -f "$SRV_TUNE_TMP/prefix/bin/srv-tune" ]
  run bash "$SRV_TUNE_TMP/prefix/bin/srv-tune" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"srv-tune"* ]]
}

@test "install.sh refuses piped stdin without --yes" {
  run bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix2" </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"Read the script first"* ]] || [[ "$output" == *"read the script"* ]] || [[ "$output" == *"not a terminal"* ]]
}

@test "install.sh refuses an apply action" {
  run bash "$SRV_TUNE_ROOT/install.sh" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"never applies"* ]]
}

@test "install.sh --tag verifies the checksum (stubbed base)" {
  if ! _file_url_works; then
    skip "host curl cannot fetch file:// URLs; covered on Linux CI"
  fi
  base="$SRV_TUNE_TMP/rel"
  mkdir -p "$base/v9.9.9" "$SRV_TUNE_TMP/pkg/srv-tune-v9.9.9"
  cp "$SRV_TUNE_ROOT/optimizer.sh" "$SRV_TUNE_ROOT/VERSION" "$SRV_TUNE_TMP/pkg/srv-tune-v9.9.9/"
  printf 'MIT\n' >"$SRV_TUNE_TMP/pkg/srv-tune-v9.9.9/LICENSE"
  tar czf "$base/v9.9.9/srv-tune-v9.9.9.tar.gz" -C "$SRV_TUNE_TMP/pkg" srv-tune-v9.9.9
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$base/v9.9.9/srv-tune-v9.9.9.tar.gz" | awk '{print $1}')"
  else
    skip "sha256sum missing on this host"
  fi
  run env SRV_TUNE_RELEASE_BASE="file://$base" bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix3" --yes --tag v9.9.9 --sha256 "$sum"
  [ "$status" -eq 0 ]
  [ -x "$SRV_TUNE_TMP/prefix3/share/srv-tune/optimizer.sh" ]
  run env SRV_TUNE_RELEASE_BASE="file://$base" bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix4" --yes --tag v9.9.9 --sha256 deadbeef
  [ "$status" -ne 0 ]
  [[ "$output" == *"mismatch"* ]]
}

@test "update verifies checksums and uninstall removes program files" {
  if ! _file_url_works; then
    skip "host curl cannot fetch file:// URLs; covered on Linux CI"
  fi
  base="$SRV_TUNE_TMP/rel2"
  mkdir -p "$base/v9.9.8" "$SRV_TUNE_TMP/pkg2/srv-tune-v9.9.8"
  cp "$SRV_TUNE_ROOT/optimizer.sh" "$SRV_TUNE_TMP/pkg2/srv-tune-v9.9.8/"
  printf '9.9.8\n' >"$SRV_TUNE_TMP/pkg2/srv-tune-v9.9.8/VERSION"
  tar czf "$base/v9.9.8/srv-tune-v9.9.8.tar.gz" -C "$SRV_TUNE_TMP/pkg2" srv-tune-v9.9.8
  if ! command -v sha256sum >/dev/null 2>&1; then
    skip "sha256sum missing on this host"
  fi
  sum="$(sha256sum "$base/v9.9.8/srv-tune-v9.9.8.tar.gz" | awk '{print $1}')"
  printf 'srv-tune-v9.9.8.tar.gz  %s\n' "$sum" >"$base/v9.9.8/sha256sums.txt"
  printf 'v9.9.8\n' >"$SRV_TUNE_TMP/apitag"
  run env SRV_TUNE_UPDATE_API_STUB="$SRV_TUNE_TMP/apitag" SRV_TUNE_RELEASE_BASE="file://$base" \
    bash -c 'source "$1"; self_update' bash "$SRV_TUNE_ROOT/lib/update.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified v9.9.8"* ]]
  run bash "$SRV_TUNE_ROOT/install.sh" --prefix "$SRV_TUNE_TMP/prefix5" --yes
  [ "$status" -eq 0 ]
  run env SRV_TUNE_PREFIX="$SRV_TUNE_TMP/prefix5" bash "$SRV_TUNE_ROOT/optimizer.sh" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_TMP/prefix5/share/srv-tune" ]
  [ ! -e "$SRV_TUNE_TMP/prefix5/bin/srv-tune" ]
}
