#!/usr/bin/env bash
# Persian UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
  app_title) printf 'بهینه‌ساز سرور srv-tune' ;;
  accept_recommended) printf 'برای پذیرش پروفایل پیشنهادی Enter را بزنید' ;;
  scan_done) printf 'اسکن کامل شد' ;;
  *) return 1 ;;
  esac
}
