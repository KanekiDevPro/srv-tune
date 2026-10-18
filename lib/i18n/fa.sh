#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Persian UI strings.
# shellcheck shell=bash

i18n_get() {
  case "$1" in
  app_title) printf 'بهینه‌ساز سرور temper' ;;
  accept_recommended) printf 'برای پذیرش پروفایل پیشنهادی Enter را بزنید' ;;
  scan_done) printf 'اسکن کامل شد' ;;
  choose_profile) printf 'پروفایل را انتخاب کنید (پیشنهادی اول است)' ;;
  risk_ssh) printf 'ریسک ssh: کانفیگ یا فایروال اشتباه شما را بیرون می‌اندازد. یک نشست سالم را باز نگه دارید. بعد از اعمال، از یک نشست NEW تایید کنید: temper confirm <id>. سکوت یعنی بازگشت خودکار.' ;;
  risk_firewall) printf 'ریسک فایروال: deny پیش‌فرض می‌تواند همین نشست و همه پورت‌ها را ببندد. اول پورت ssh باز می‌شود و بازگشت خودکار زمان‌دار مسلح است. از نشست NEW تایید کنید.' ;;
  type_ssh) printf 'برای اعمال تغییرات ssh بنویسید SSH-YES (غیر آن یعنی انصراف)' ;;
  type_firewall) printf 'برای اعمال تغییرات فایروال بنویسید FIREWALL-YES (غیر آن یعنی انصراف)' ;;
  need_with_ssh) printf 'ماژول ssh به --with-ssh و تایید تایپی نیاز دارد (ریسک‌ها بالا)' ;;
  need_with_firewall) printf 'فایروال/fail2ban به --with-firewall و تایید تایپی نیاز دارد (ریسک‌ها بالا)' ;;
  need_with_registry) printf 'میرورهای رجیستری به --with-registry و تایید تایپی نیاز دارند (ریسک‌ها بالا)' ;;
  risk_registry) printf 'ریسک میرور رجیستری: مثل apt امضا ندارند؛ اپراتور میرور می‌تواند بسته دست‌کاری‌شده بدهد. مالک و داک را در data/ ببینید. فقط HTTPS. هرگز در پروفایل پیش‌فرض نیست.' ;;
  type_registry) printf 'برای اعمال میرور رجیستری بنویسید REGISTRY-YES (غیر آن یعنی انصراف)' ;;
  risk_dns_extra) printf 'ریسک ریزالور اضافه: ریزالور شخص ثالث همه کوئری‌ها را می‌بیند و ممکن است پاسخ دست‌کاری‌شده بدهد (سانسور، هایجک). فقط ریزالوری که به آن اعتماد دارید. اضافه‌ها هرگز خودکار انتخاب نمی‌شوند.' ;;
  type_dns_extra) printf 'برای استفاده از ریزالور اضافه بنویسید DNS-EXTRA-YES (غیر آن یعنی انصراف)' ;;
  aborted) printf 'توسط شما لغو شد، چیزی تغییر نکرد' ;;
  tunnel_title) printf 'تونل' ;;
  tunnel_keys) printf 'کلیدها' ;;
  tunnel_access) printf 'سیاست دسترسی' ;;
  tunnel_sessions) printf 'نشست‌ها' ;;
  tunnel_refresh) printf 'به‌روزرسانی' ;;
  tunnel_quit) printf 'خروج' ;;
  tunnel_back) printf 'بازگشت' ;;
  tunnel_add) printf 'افزودن' ;;
  tunnel_remove) printf 'حذف' ;;
  tunnel_list) printf 'فهرست' ;;
  tunnel_edit) printf 'ویرایش' ;;
  tunnel_permits) printf 'PermitOpen (none یا host:port[,host:port])' ;;
  tunnel_gateway) printf 'GatewayPorts (yes/no)' ;;
  tunnel_risk) printf 'ریسک: این کار drop-in تونل sshd را بازنویسی می‌کند؛ مقدار اشتباه دسترسی خودتان را قطع می‌کند. بعد از reload، قبل از انقضای گارد از یک نشست NEW مطمئن شوید.' ;;
  tunnel_confirm) printf 'برای بازنویسی سیاست دسترسی تونل SSH-YES را تایپ کنید:' ;;
  *) return 1 ;;
  esac
}
