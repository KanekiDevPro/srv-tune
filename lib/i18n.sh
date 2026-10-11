#!/usr/bin/env bash
# Minimal i18n: UI strings via dictionaries, default en, --lang fa available.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_I18N_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_I18N_SOURCED=1

# shellcheck disable=SC1091
source_lib() {
  local f="$1"
  # shellcheck disable=SC1090
  source "$f"
}

srv_tune_lang() {
  case "${SRV_TUNE_LANG:-en}" in
  fa) printf 'fa\n' ;;
  *) printf 'en\n' ;;
  esac
}

# t KEY — prints translated UI string. Code/logs stay English.
t() {
  local key="$1"
  local lang
  lang="$(srv_tune_lang)"
  local root="${SRV_TUNE_ROOT:-.}"
  local dict="$root/lib/i18n/${lang}.sh"
  local fallback="$root/lib/i18n/en.sh"
  local val=""
  if [[ -f "$dict" ]]; then
    # Each dict defines t_<key>() or associative lookup via case.
    val="$("bash" -c "source '$dict'; i18n_get '$key'" 2>/dev/null || true)"
  fi
  if [[ -z "$val" && -f "$fallback" && "$dict" != "$fallback" ]]; then
    val="$("bash" -c "source '$fallback'; i18n_get '$key'" 2>/dev/null || true)"
  fi
  if [[ -z "$val" ]]; then
    printf '%s\n' "$key"
  else
    printf '%s\n' "$val"
  fi
}
