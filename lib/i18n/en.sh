#!/usr/bin/env bash
# English UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
    app_title) printf 'srv-tune server optimizer' ;;
    accept_recommended) printf 'Press Enter to accept the recommended profile' ;;
    scan_done) printf 'Scan complete' ;;
    *) return 1 ;;
  esac
}
