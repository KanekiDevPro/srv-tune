#!/usr/bin/env bash
# pip_mirror: system pip index-url from data/mirrors-pip.list.
# Tool-gated: skips (2) unless pip is installed. Never touches user configs.
# Contract: pip_mirror_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash

pip_mirror_have() {
  # SRV_TUNE_PIP_BIN overrides detection (tests): "none" forces absent.
  if [[ "${SRV_TUNE_PIP_BIN:-}" == "none" ]]; then
    return 1
  fi
  if [[ -n "${SRV_TUNE_PIP_BIN:-}" ]]; then
    return 0
  fi
  command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1
}

pip_mirror_url() {
  registry_pick_url "${SRV_TUNE_ROOT:-.}/data/mirrors-pip.list"
}

pip_mirror_detect() {
  if pip_mirror_have; then
    printf 'PRESENT=yes\n'
  else
    printf 'PRESENT=no\n'
  fi
  printf 'URL=%s\n' "$(pip_mirror_url || printf none)"
}

pip_mirror_recommend() {
  if ! pip_mirror_have; then
    printf 'skip: pip not installed (why: nothing to configure)\n'
    return 0
  fi
  printf 'index-url %s (why: curated entry, override with --mirror URL)\n' "$(pip_mirror_url)"
  printf 'warn: registry mirrors are NOT signed like apt (why: a mirror operator can serve altered packages; review the owner/docs in data/mirrors-pip.list)\n'
}

pip_mirror_apply() {
  local backup_dir="$1" url tmp
  if ! pip_mirror_have; then
    printf 'skip: pip not installed\n'
    return 2
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  url="$(pip_mirror_url)" || {
    printf 'error: no pip mirror configured\n' >&2
    return 1
  }
  tmp="$(mktemp)"
  printf '# srv-tune pip mirror\n[global]\nindex-url = %s\n' "$url" >"$tmp"
  apply_file "$backup_dir" "$(sys_p /etc/pip.conf)" "$tmp" "pip index $url" || return 1
  return 0
}

pip_mirror_verify() {
  local f url
  f="$(sys_p /etc/pip.conf)"
  if [[ ! -f "$f" ]]; then
    printf 'error: pip.conf missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q '^index-url' "$f" || {
    printf 'error: index-url missing in %s\n' "$f" >&2
    return 1
  }
  url="$(grep '^index-url' "$f" | head -n 1 | awk '{print $3}')"
  if ! registry_reachable "$url"; then
    printf 'error: mirror unreachable, rolling back: %s\n' "$url" >&2
    return 1
  fi
  return 0
}
