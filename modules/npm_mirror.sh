#!/usr/bin/env bash
# npm_mirror: system npm registry from data/mirrors-npm.list.
# Tool-gated: skips (2) unless npm is installed. Writes /etc/npmrc only.
# Contract: npm_mirror_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash

npm_mirror_have() {
  # SRV_TUNE_NPM_BIN overrides detection (tests): "none" forces absent.
  if [[ "${SRV_TUNE_NPM_BIN:-}" == "none" ]]; then
    return 1
  fi
  if [[ -n "${SRV_TUNE_NPM_BIN:-}" ]]; then
    return 0
  fi
  command -v npm >/dev/null 2>&1
}

npm_mirror_url() {
  registry_pick_url "${SRV_TUNE_ROOT:-.}/data/mirrors-npm.list"
}

npm_mirror_detect() {
  if npm_mirror_have; then
    printf 'PRESENT=yes\n'
  else
    printf 'PRESENT=no\n'
  fi
  printf 'URL=%s\n' "$(npm_mirror_url || printf none)"
}

npm_mirror_recommend() {
  if ! npm_mirror_have; then
    printf 'skip: npm not installed (why: nothing to configure)\n'
    return 0
  fi
  printf 'registry %s (why: curated entry, override with --mirror URL)\n' "$(npm_mirror_url)"
  printf 'warn: registry mirrors are NOT signed like apt (why: a mirror operator can serve altered packages; review the owner/docs in data/mirrors-npm.list)\n'
}

npm_mirror_apply() {
  local backup_dir="$1" url tmp
  if ! npm_mirror_have; then
    printf 'skip: npm not installed\n'
    return 2
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  url="$(npm_mirror_url)" || {
    printf 'error: no npm mirror configured\n' >&2
    return 1
  }
  tmp="$(mktemp)"
  printf '# srv-tune npm mirror\nregistry=%s\n' "$url" >"$tmp"
  apply_file "$backup_dir" "$(sys_p /etc/npmrc)" "$tmp" "npm registry $url" || return 1
  return 0
}

npm_mirror_verify() {
  local f url
  f="$(sys_p /etc/npmrc)"
  if [[ ! -f "$f" ]]; then
    printf 'error: npmrc missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q '^registry=' "$f" || {
    printf 'error: registry= missing in %s\n' "$f" >&2
    return 1
  }
  url="$(grep '^registry=' "$f" | head -n 1 | cut -d= -f2-)"
  if ! registry_reachable "$url"; then
    printf 'error: mirror unreachable, rolling back: %s\n' "$url" >&2
    return 1
  fi
  return 0
}
