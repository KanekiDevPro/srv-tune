#!/usr/bin/env bash
# Persian UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
    app_title) printf 'بهینه‌ساز سرور srv-tune' ;;
    accept_recommended) printf 'برای پذیرش پروفایل پیشنهادی Enter را بزنید' ;;
    scan_done) printf 'اسکن کامل شد' ;;
    choose_profile) printf 'پروفایل را انتخاب کنید (پیشنهادی اول است)' ;;
    risk_ssh) printf 'ریسک ssh: کانفیگ یا فایروال اشتباه شما را بیرون می‌اندازد. یک نشست سالم را باز نگه دارید. بعد از اعمال، از یک نشست NEW تایید کنید: srv-tune confirm <id>. سکوت یعنی بازگشت خودکار.' ;;
    risk_firewall) printf 'ریسک فایروال: deny پیش‌فرض می‌تواند همین نشست و همه پورت‌ها را ببندد. اول پورت ssh باز می‌شود و بازگشت خودکار زمان‌دار مسلح است. از نشست NEW تایید کنید.' ;;
    type_ssh) printf 'برای اعمال تغییرات ssh بنویسید SSH-YES (غیر آن یعنی انصراف)' ;;
    type_firewall) printf 'برای اعمال تغییرات فایروال بنویسید FIREWALL-YES (غیر آن یعنی انصراف)' ;;
    need_with_ssh) printf 'ماژول ssh به --with-ssh و تایید تایپی نیاز دارد (ریسک‌ها بالا)' ;;
    need_with_firewall) printf 'فایروال/fail2ban به --with-firewall و تایید تایپی نیاز دارد (ریسک‌ها بالا)' ;;
    aborted) printf 'توسط شما لغو شد، چیزی تغییر نکرد' ;;
    *) return 1 ;;
  esac
}
