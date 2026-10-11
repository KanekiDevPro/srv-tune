#!/usr/bin/env bash
# UI helpers: whiptail if present else plain prompts. Never auto-install deps.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_UI_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_UI_SOURCED=1

ui_confirm_default_yes() {
  # $1 = prompt text. One Enter accepts. --yes bypasses.
  local prompt="$1"
  if [[ "${SRV_TUNE_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
    whiptail --yesno "$prompt" 8 70 3>&1 1>&2 2>&3
    return $?
  fi
  printf '%s [Enter=yes, n=no]: ' "$prompt"
  local ans=""
  IFS= read -r ans || true
  case "$ans" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

ui_info() {
  printf '%s\n' "$*"
}
