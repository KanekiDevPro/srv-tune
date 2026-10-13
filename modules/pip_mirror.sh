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
  local root="${SRV_TUNE_ROOT:-.}" line
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    printf '%s\n' "$line" | awk '{print $1}'
    return 0
  done <"$root/data/mirrors-pip.list" 2>/dev/null
  return 1
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
  printf 'index-url %s (why: first responsive entry in mirrors-pip.list)\n' "$(pip_mirror_url)"
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
  local f
  f="$(sys_p /etc/pip.conf)"
  if [[ ! -f "$f" ]]; then
    printf 'error: pip.conf missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q '^index-url' "$f" || {
    printf 'error: index-url missing in %s\n' "$f" >&2
    return 1
  }
  return 0
}
