#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# mirror: benchmark distro mirrors live, swap only the URI, verify with
# apt update; pip/npm/docker registry mirrors are tool-gated file writes.
# Benchmarks: 10s timeout, max 4 parallel, contacted hosts always printed.
# Third-party repos (URIs outside the candidate set) are never touched.
# Contract: mirror_detect|recommend|apply|verify|benchmark|winner.
# 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

mirror_os_id() {
  local f="${TEMPER_OS_RELEASE:-/etc/os-release}" id
  id="$(grep -E '^ID=' "$f" 2>/dev/null | tail -n 1 | cut -d= -f2 | tr -d '"' || true)"
  [[ -z "$id" ]] && id="unknown"
  printf '%s\n' "$id"
}

mirror_list_file() {
  local root="${TEMPER_ROOT:-.}" id
  id="$(mirror_os_id)"
  case "$id" in
  ubuntu) printf '%s/data/mirrors-ubuntu.list\n' "$root" ;;
  debian) printf '%s/data/mirrors-debian.list\n' "$root" ;;
  *) printf '%s/data/mirrors-debian.list\n' "$root" ;;
  esac
}

mirror_candidates() {
  local f line url
  f="$(mirror_list_file)"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    esac
    # Fail closed: unverified entries are invisible unless a human
    # verified them (or the test-only override is active).
    data_entry_verified "$line" || continue
    url="$(printf '%s' "$line" | awk '{print $1}')"
    [[ -n "$url" ]] && printf '%s\n' "$url"
  done <"$f"
}

# mirror_bench_one <url> <out> - curl timing; appends "secs code url ok|fail".
mirror_bench_one() {
  local url="$1" out="$2" res secs code
  res="$(curl -s -o /dev/null -w '%{time_total} %{http_code}' --max-time 10 "$url" 2>/dev/null || printf '0 000')"
  secs="$(printf '%s' "$res" | awk '{print $1}')"
  code="$(printf '%s' "$res" | awk '{print $2}')"
  if [[ "$code" == "000" ]]; then
    printf '0 000 %s fail\n' "$url" >>"$out"
  else
    printf '%s %s %s ok\n' "$secs" "$code" "$url" >>"$out"
  fi
}

# mirror_benchmark - one bounded round; prints "secs code url ok|fail" sorted.
mirror_benchmark() {
  local tmp url
  tmp="$(mktemp)"
  printf 'contacting mirrors:' >&2
  while IFS= read -r url; do
    printf ' %s' "$url" >&2
  done < <(mirror_candidates)
  printf '\n' >&2
  while IFS= read -r url; do
    while [[ "$(jobs -r | wc -l)" -ge 4 ]]; do
      wait -n 2>/dev/null || wait
    done
    mirror_bench_one "$url" "$tmp" &
  done < <(mirror_candidates)
  wait
  sort -s -t' ' -k1,1n "$tmp"
  rm -f "$tmp"
}

# mirror_winner - fastest reachable URL, empty when all fail.
mirror_winner() {
  mirror_benchmark 2>/dev/null | awk '$4=="ok" {print $3; exit}'
}

mirror_apt_files() {
  local base
  base="$(sys_p /etc/apt)"
  [[ -f "$base/sources.list" ]] && printf '%s\n' "$base/sources.list"
  local f
  for f in "$base"/sources.list.d/*.list "$base"/sources.list.d/*.sources; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
}

mirror_validate_file() {
  # mirror_validate_file <file> [format_source] - format follows the source
  # name because swapped content sits in extension-less tmp files.
  local f="$1" fmt="${2:-$1}"
  case "$fmt" in
  *.sources)
    grep -q '^Types:' "$f" && grep -q '^URIs:' "$f" && grep -q '^Suites:' "$f"
    ;;
  *)
    # every non-comment, non-empty line starts with a valid type.
    ! grep -Ev '^[[:space:]]*(#|$)' "$f" | grep -Ev '^(deb|deb-src) ' | grep -q .
    ;;
  esac
}

mirror_detect() {
  printf 'DISTRO=%s\n' "$(mirror_os_id)"
  local f found=0
  while IFS= read -r f; do
    found=1
    printf 'FILE=%s\n' "$f"
  done < <(mirror_apt_files)
  if [[ "$found" == "0" ]]; then
    printf 'FILE=none\n'
  fi
  if command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
    printf 'PIP=yes\n'
  else
    printf 'PIP=no\n'
  fi
  if command -v npm >/dev/null 2>&1; then printf 'NPM=yes\n'; else printf 'NPM=no\n'; fi
  if command -v docker >/dev/null 2>&1; then printf 'DOCKER=yes\n'; else printf 'DOCKER=no\n'; fi
}

mirror_recommend() {
  printf 'benchmark (%s list; why: live timing from THIS server):\n' "$(mirror_os_id)"
  mirror_benchmark
  printf 'pick: fastest reachable as the single URI (why: one source, no duplicates)\n'
}

mirror_apply() {
  local backup_dir="$1" winner f url tmp touched
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  winner="$(mirror_winner)"
  if [[ -z "$winner" ]]; then
    printf 'error: every mirror failed; refusing to apply\n' >&2
    return 1
  fi
  touched=0
  while IFS= read -r f; do
    # Token-level swap of candidate URIs only (never third-party repos).
    # Trailing slashes are normalized: lists carry them, files often not.
    tmp="$(mktemp)"
    if awk -v winner="$winner" '
      FILENAME == ARGV[1] {
        if ($1 !~ /^#/ && $1 != "") {
          k = $1
          sub(/\/$/, "", k)
          c[k] = 1
        }
        next
      }
      /^[[:space:]]*#/ { print; next }
      {
        for (i = 1; i <= NF; i++) {
          b = $i
          sub(/\/$/, "", b)
          wb = winner
          sub(/\/$/, "", wb)
          if ((b in c) && (b != wb)) { $i = winner; touched = 1 }
        }
        print
      }
      END { exit !touched }
    ' <(mirror_candidates) "$f" >"$tmp"; then
      if ! mirror_validate_file "$tmp" "$f"; then
        printf 'error: swap would break %s; refusing\n' "$f" >&2
        rm -f "$tmp"
        return 1
      fi
      apply_file "$backup_dir" "$f" "$tmp" "mirror -> $winner" || return 1
      touched=1
    else
      rm -f "$tmp"
    fi
  done < <(mirror_apt_files)
  if [[ "$touched" == "0" ]]; then
    printf 'note: no candidate URI found in apt files (already on %s or third-party only)\n' "$winner"
  fi
  return 0
}

mirror_verify() {
  local f fail
  fail=0
  while IFS= read -r f; do
    if ! mirror_validate_file "$f"; then
      printf 'error: invalid apt file after apply: %s\n' "$f" >&2
      fail=1
    fi
    # Never bless weakened trust: these options must not appear, in either
    # format. The greps below only ever refuse such files, never write them.
    if grep -Eqi 'trusted[[:space:]]*[:=][[:space:]]*yes' "$f" 2>/dev/null; then
      printf 'error: %s weakens trust (trusted=yes); refusing\n' "$f" >&2
      fail=1
    fi
    if grep -Eqi 'allow-insecure' "$f" 2>/dev/null; then
      printf 'error: %s weakens trust (allow-insecure); refusing\n' "$f" >&2
      fail=1
    fi
  done < <(mirror_apt_files)
  if [[ "$fail" -ne 0 ]]; then
    return 1
  fi
  mirror_suite_warn || true
  mirror_freshness_warn || true
  if [[ "${TEMPER_TEST:-0}" == "1" && "${TEMPER_FORCE_LIVE_VERIFY:-0}" != "1" ]]; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    if ! apt-get update -o Debug::NoLocking=1 >/dev/null 2>&1 && ! apt-get update >/dev/null 2>&1; then
      printf 'error: apt-get update failed after mirror apply\n' >&2
      return 1
    fi
  fi
  return 0
}

# mirror_suite_warn - security suite should be configured somewhere.
mirror_suite_warn() {
  local found=0 f
  while IFS= read -r f; do
    if grep -Eq '\-security|/security|security\.debian\.org|ubuntu.*security|esm' "$f" 2>/dev/null; then
      found=1
    fi
  done < <(mirror_apt_files)
  if [[ "$found" == "0" ]]; then
    printf 'warn: no security suite configured in apt sources (why: security updates need a security line)\n'
  fi
  return 0
}

# mirror_freshness_warn - apt lists older than 7 days suggest a stale mirror.
mirror_freshness_warn() {
  local stamp
  stamp="$(sys_p /var/lib/apt/periodic/update-stamp)"
  if [[ ! -f "$stamp" ]]; then
    return 0
  fi
  if find "$stamp" -mtime +7 2>/dev/null | grep -q .; then
    printf 'warn: apt update stamp is older than 7 days (why: mirror may be stale)\n'
  fi
  return 0
}
