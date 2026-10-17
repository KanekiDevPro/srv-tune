#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Scan diff: compare a stored scanner JSON against the current scan.
# Reporting only: exit 0 on success, 2 when the baseline is unusable.
# shellcheck shell=bash

# scan_diff_parse_json <flat-json-file> - print KEY<TAB>VALUE lines.
# Not a general JSON parser: only the scanner's one-line flat
# {"K":"V",...} format is supported.
# shortcut: a value containing the raw sequence "," (or nested JSON)
# breaks the split; upgrade to a real parser if that ever changes.
scan_diff_parse_json() {
  sed -e 's/^{//' -e 's/}$//' -e 's/^"//' -e 's/"$//' "$1" |
    awk '{ gsub(/","/, "\n"); print }' |
    while IFS= read -r pair; do
      case "$pair" in
      *'":"'*) ;;
      *) continue ;;
      esac
      printf '%s\t%s\n' "${pair%%\":\"*}" "${pair#*\":\"}"
    done
}

# scan_diff_run <baseline.json> <current.env> <new_score> <new_profile>
# current.env is the scan's KEY=VALUE dump (no SCORE/PROFILE lines).
scan_diff_run() {
  local base="$1" cur="$2" new_score="$3" new_profile="$4"
  local -A old=()
  local -A seen=()
  local k v changed=0 added=0 removed=0 total=0
  if [[ ! -f "$base" ]]; then
    printf 'error: baseline not found: %s\n' "$base" >&2
    return 2
  fi
  local pairs
  pairs="$(scan_diff_parse_json "$base" || true)"
  while IFS=$'\t' read -r k v; do
    [[ -z "$k" ]] && continue
    old["$k"]="$v"
  done <<<"$pairs"
  if [[ "${#old[@]}" -eq 0 ]]; then
    printf 'error: baseline has no KEY/VALUE pairs (flat scan JSON expected): %s\n' "$base" >&2
    return 2
  fi
  # SCORE and PROFILE live in the baseline JSON but not in current.env;
  # they are compared explicitly below, never as added/removed keys.
  seen[SCORE]=1
  seen[PROFILE]=1
  printf 'scan diff: %s -> live scan\n' "$base"
  if [[ "${old[SCORE]:-?}" == "$new_score" ]]; then
    printf 'score:   %s (unchanged)\n' "$new_score"
  else
    printf 'score:   %s -> %s\n' "${old[SCORE]:-?}" "$new_score"
  fi
  if [[ "${old[PROFILE]:-?}" == "$new_profile" ]]; then
    printf 'profile: %s (unchanged)\n' "$new_profile"
  else
    printf 'profile: %s -> %s\n' "${old[PROFILE]:-?}" "$new_profile"
  fi
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    [[ -n "${seen[$k]:-}" ]] && continue
    seen["$k"]=1
    total=$((total + 1))
    if [[ -z "${old[$k]+x}" ]]; then
      printf 'added   %s: %s\n' "$k" "$v"
      added=$((added + 1))
    elif [[ "${old[$k]}" != "$v" ]]; then
      printf 'changed %s: %s -> %s\n' "$k" "${old[$k]}" "$v"
      changed=$((changed + 1))
    fi
  done <"$cur"
  for k in "${!old[@]}"; do
    [[ -n "${seen[$k]:-}" ]] && continue
    printf 'removed %s: %s\n' "$k" "${old[$k]}"
    removed=$((removed + 1))
  done
  if [[ $((changed + added + removed)) -eq 0 ]]; then
    printf 'scan diff: no changes (%s keys)\n' "$total"
  else
    printf 'scan diff: %s changed, %s added, %s removed (%s keys)\n' \
      "$changed" "$added" "$removed" "$total"
  fi
  return 0
}
