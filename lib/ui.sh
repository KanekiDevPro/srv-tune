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
  [nN] | [nN][oO]) return 1 ;;
  *) return 0 ;;
  esac
}

ui_info() {
  printf '%s\n' "$*"
}

ui_type_confirm() {
  # $1 = prompt text, $2 = exact phrase to type. --yes bypasses (automation).
  local prompt="$1" expected="$2" ans=""
  if [[ "${SRV_TUNE_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
    ans="$(whiptail --inputbox "$prompt" 10 70 3>&1 1>&2 2>&3)" || return 1
  else
    printf '%s ' "$prompt"
    IFS= read -r ans || return 1
  fi
  [[ "$ans" == "$expected" ]]
}

ui_menu() {
  # $1 = title, $2 = default, $3.. = options. Prints the choice. --yes or
  # non-tty returns the default without prompting.
  local title="$1" default="$2"
  shift 2
  local opts=("$@") i choice
  if [[ "${SRV_TUNE_ASSUME_YES:-0}" == "1" ]] || [[ ! -t 0 ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  if command -v whiptail >/dev/null 2>&1; then
    local tags=() n=1
    for i in "${opts[@]}"; do
      tags+=("$n" "$i")
      n=$((n + 1))
    done
    choice="$(whiptail --title "$title" --menu "$title" 15 60 7 "${tags[@]}" 3>&1 1>&2 2>&3)" || {
      printf '%s\n' "$default"
      return 0
    }
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#opts[@]}" ]]; then
      printf '%s\n' "${opts[$((choice - 1))]}"
    else
      printf '%s\n' "$choice"
    fi
    return 0
  fi
  printf '%s\n' "$title"
  i=1
  for choice in "${opts[@]}"; do
    printf '  %s) %s\n' "$i" "$choice"
    i=$((i + 1))
  done
  printf 'Choice [%s]: ' "$default"
  IFS= read -r choice || true
  if [[ -z "$choice" ]]; then
    printf '%s\n' "$default"
    return 0
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#opts[@]}" ]]; then
    printf '%s\n' "${opts[$((choice - 1))]}"
    return 0
  fi
  for i in "${opts[@]}"; do
    if [[ "$i" == "$choice" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  printf '%s\n' "$default"
  return 0
}
