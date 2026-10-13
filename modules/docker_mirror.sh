#!/usr/bin/env bash
# docker_mirror: registry-mirrors for the docker daemon.
# Tool-gated: skips (2) unless docker is installed. Writes daemon.json ONLY
# when absent; an existing file is never merged or overwritten (operator owns
# it). JSON validity checked with python3 when available, else key grep.
# Contract: docker_mirror_detect|recommend|apply|verify. 0/2/1.
# SPDX-License-Identifier: MIT
# shellcheck shell=bash

docker_mirror_have() {
  # SRV_TUNE_DOCKER_BIN overrides detection (tests): "none" forces absent.
  if [[ "${SRV_TUNE_DOCKER_BIN:-}" == "none" ]]; then
    return 1
  fi
  if [[ -n "${SRV_TUNE_DOCKER_BIN:-}" ]]; then
    return 0
  fi
  command -v docker >/dev/null 2>&1
}

docker_mirror_url() {
  local root="${SRV_TUNE_ROOT:-.}" line
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    printf '%s\n' "$line" | awk '{print $1}'
    return 0
  done <"$root/data/mirrors-docker.list" 2>/dev/null
  return 1
}

docker_mirror_detect() {
  if docker_mirror_have; then
    printf 'PRESENT=yes\n'
  else
    printf 'PRESENT=no\n'
  fi
  printf 'URL=%s\n' "$(docker_mirror_url || printf none)"
}

docker_mirror_recommend() {
  if ! docker_mirror_have; then
    printf 'skip: docker not installed (why: nothing to configure)\n'
    return 0
  fi
  printf 'registry-mirrors %s (why: first entry in mirrors-docker.list; existing daemon.json never touched)\n' "$(docker_mirror_url)"
}

docker_mirror_apply() {
  local backup_dir="$1" url tmp f
  if ! docker_mirror_have; then
    printf 'skip: docker not installed\n'
    return 2
  fi
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  url="$(docker_mirror_url)" || {
    printf 'error: no docker mirror configured\n' >&2
    return 1
  }
  f="$(sys_p /etc/docker/daemon.json)"
  if [[ -f "$f" ]]; then
    printf 'skip: %s exists (why: operator-owned; merge it by hand)\n' "$f"
    return 2
  fi
  tmp="$(mktemp)"
  printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$url" >"$tmp"
  apply_file "$backup_dir" "$f" "$tmp" "docker registry mirror" || return 1
  return 0
}

docker_mirror_verify() {
  local f
  f="$(sys_p /etc/docker/daemon.json)"
  if [[ ! -f "$f" ]]; then
    printf 'error: daemon.json missing: %s\n' "$f" >&2
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" || {
      printf 'error: daemon.json is not valid JSON\n' >&2
      return 1
    }
  else
    grep -q 'registry-mirrors' "$f" || {
      printf 'error: registry-mirrors missing in %s\n' "$f" >&2
      return 1
    }
  fi
  return 0
}
