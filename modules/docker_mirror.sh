#!/usr/bin/env bash
# docker_mirror: registry-mirrors for the docker daemon.
# Tool-gated + --with-registry opt-in: skips (2) unless docker is installed.
# Merges daemon.json preserving all keys (validates JSON, backup first).
# HTTPS only. Warns daemon restart affects containers; never restarts automatically.
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
  registry_pick_url "${SRV_TUNE_ROOT:-.}/data/mirrors-docker.list"
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
  printf 'registry-mirrors %s (why: curated entry, override with --mirror URL)\n' "$(docker_mirror_url)"
  printf 'warn: registry mirrors are NOT signed like apt (why: a mirror operator can serve altered images)\n'
  printf 'warn: registry-mirrors needs a daemon RESTART (why: not in the SIGHUP-reloadable set per Docker docs); restart affects running containers and is NEVER automatic\n'
}

# docker_json_tool - merge backend: python3, jq, or none (refuse to merge).
docker_json_tool() {
  if [[ -n "${SRV_TUNE_JSON_TOOL:-}" ]]; then
    printf '%s\n' "$SRV_TUNE_JSON_TOOL"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3\n'
  elif command -v jq >/dev/null 2>&1; then
    printf 'jq\n'
  else
    printf 'none\n'
  fi
}

# docker_merge_mirrors <existing> <url> <out> - merge preserving all keys.
docker_merge_mirrors() {
  local existing="$1" url="$2" out="$3" tool
  tool="$(docker_json_tool)"
  # Validate the existing file first: never merge garbage.
  if [[ "$tool" == "python3" ]]; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$existing" || {
      printf 'error: existing daemon.json is not valid JSON; refusing to merge\n' >&2
      return 1
    }
    SRV_TUNE_MERGE_URL="$url" python3 -c '
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
doc = json.load(open(src))
cur = doc.get("registry-mirrors", [])
if not isinstance(cur, list):
    print("error: registry-mirrors is not a list", file=sys.stderr)
    sys.exit(1)
if os.environ["SRV_TUNE_MERGE_URL"] not in cur:
    cur.append(os.environ["SRV_TUNE_MERGE_URL"])
doc["registry-mirrors"] = cur
json.dump(doc, open(dst, "w"), indent=2)
' "$existing" "$out" || return 1
  elif [[ "$tool" == "jq" ]]; then
    jq --arg u "$url" '.["registry-mirrors"] |= ((. // []) + [$u] | unique)' "$existing" >"$out" || {
      printf 'error: existing daemon.json is not valid JSON; refusing to merge\n' >&2
      return 1
    }
  else
    printf 'error: cannot merge daemon.json without python3 or jq (refusing blind overwrite)\n' >&2
    return 1
  fi
  return 0
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
  tmp="$(mktemp)"
  if [[ -f "$f" ]]; then
    # MERGE preserving every existing key (backup first via apply_file).
    if ! docker_merge_mirrors "$f" "$url" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
  else
    printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$url" >"$tmp"
  fi
  if ! apply_file "$backup_dir" "$f" "$tmp" "docker registry mirror"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  printf 'warn: restart the docker daemon yourself to take effect (why: registry-mirrors is not SIGHUP-reloadable; restart affects running containers; never automatic)\n'
  return 0
}

docker_mirror_verify() {
  local f url
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
  url="$(docker_mirror_url 2>/dev/null || printf '')"
  if [[ -n "$url" ]] && ! registry_reachable "$url"; then
    printf 'error: mirror unreachable, rolling back: %s\n' "$url" >&2
    return 1
  fi
  return 0
}
