#!/usr/bin/env bash
# Small portable utilities. No GNU-only flags.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_UTIL_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_UTIL_SOURCED=1

is_root() {
  [[ "${EUID:-$(id -u)}" == "0" ]]
}

# read_kv_file <file> <key> - portable KEY=VALUE reader, no PCRE.
read_kv_file() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"'
}

# json_escape - minimal escaper for strings we emit.
json_escape() {
  local s="$1"
  printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ' | tr '\t' ' '
}
# show_diff <old> <new> - unified diff, no color dependency.
show_diff() {
  if command -v diff >/dev/null 2>&1; then
    diff -u "$1" "$2" || true
  else
    printf '(diff not available)\n'
  fi
}
