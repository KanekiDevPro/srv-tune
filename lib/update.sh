#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Self-update: explicit only, checksum-verified, no telemetry.
# Uses SRV_TUNE_RELEASE_BASE (default: GitHub releases) and refuses on any
# checksum mismatch. Testable offline via file:// base URLs.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_UPDATE_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_UPDATE_SOURCED=1

self_update() {
  local repo="${SRV_TUNE_UPDATE_REPO:-KanekiDevPro/srv-tune}"
  local root="${SRV_TUNE_ROOT:-.}"
  local cur ver_file tag sums
  ver_file="$root/VERSION"
  cur="$(cat "$ver_file" 2>/dev/null || printf '0.0.0')"
  local base="${SRV_TUNE_RELEASE_BASE:-https://github.com/$repo/releases/download}"
  local api="https://api.github.com/repos/$repo/releases/latest"
  if [[ -n "${SRV_TUNE_UPDATE_API_STUB:-}" ]]; then
    tag="$(cat "${SRV_TUNE_UPDATE_API_STUB}" 2>/dev/null || printf '')"
  else
    command -v curl >/dev/null 2>&1 || {
      printf 'error: update needs curl\n' >&2
      return 1
    }
    tag="$(curl -fsSL --max-time 20 "$api" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"
  fi
  if [[ -z "$tag" ]]; then
    printf 'error: could not determine the latest release\n' >&2
    return 1
  fi
  if [[ "$tag" == "v$cur" || "$tag" == "$cur" ]]; then
    printf 'already up to date (%s)\n' "$cur"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # expanded now on purpose: $tmp is local gone at RETURN
  trap "rm -rf '$tmp'" RETURN
  printf 'downloading %s ...\n' "$tag"
  curl -fsSL --max-time 120 "$base/$tag/srv-tune-$tag.tar.gz" -o "$tmp/pkg.tar.gz" || {
    printf 'error: download failed\n' >&2
    return 1
  }
  sums="$(curl -fsSL --max-time 60 "$base/$tag/sha256sums.txt" 2>/dev/null || printf '')"
  if [[ -z "$sums" ]]; then
    printf 'error: no sha256sums.txt for %s; refusing\n' "$tag" >&2
    return 1
  fi
  local want actual
  want="$(printf '%s' "$sums" | awk '$2 ~ /\.tar\.gz$/ {print $1}' | head -n 1)"
  actual="$(sha256sum "$tmp/pkg.tar.gz" | awk '{print $1}')"
  if [[ -z "$want" || "$want" != "$actual" ]]; then
    printf 'error: checksum mismatch for %s (refusing)\n' "$tag" >&2
    return 1
  fi
  printf 'verified %s (%s); reinstall with install.sh --tag %s --sha256 %s\n' "$tag" "$actual" "$tag" "$actual"
  trap - RETURN
  printf '%s\n' "$tmp/pkg.tar.gz"
  return 0
}

do_uninstall() {
  local prefix="${1:-/usr/local}" dest link
  dest="$prefix/share/srv-tune"
  link="$prefix/bin/srv-tune"
  rm -f "$link"
  if [[ -d "$dest" ]]; then
    rm -rf "$dest"
  fi
  printf 'removed program files under %s\n' "$prefix"
  printf 'system config drop-ins were left in place on purpose.\n'
  printf 'restore them with: srv-tune list-backups  (before uninstall) or re-install and rollback.\n'
}
