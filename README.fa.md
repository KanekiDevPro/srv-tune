# srv-tune — بهینه‌ساز سرور لینوکس

SCAN -> RECOMMEND -> APPLY -> VERIFY -> ROLLBACK-IF-BROKEN.

![demo](docs/demo.gif)
*(جای GIF نمایشی: خروجی `scan` و `apply --dry-run` را روی VM تمیز ضبط کنید.)*

## محدوده صادقانه

- ماژول‌های اصلی = **پایدار**: ‏limits‏، ‏network‏، ‏kernel‏، ‏dns‏، ‏mirror‏.
- ‏ssh‏، ‏firewall‏، ‏fail2ban‏ = **آزمایشی**: فقط با فلگ صریح
  (‏--with-ssh‏ / ‏--with-firewall‏) و تایید تایپی، زیر گارد بازگشت خودکار.
  بدون خواندن ‏docs/TESTING-VM.md‏ استفاده نکنید.

## سیستم‌های پشتیبانی‌شده

Tier 1: ‏Ubuntu 24.04‏، ‏26.04‏، ‏Debian 13‏. Tier 2: ‏Ubuntu 22.04‏، ‏Debian 12‏.
‏Ubuntu 20.04‏: بهترین تلاش. ‏Debian 11‏ منقضی است: هشدار + توقف apply.

## مدل امنیت

- بکاپ همه فایل‌ها قبل تغییر + ‏rollback‏. نوشتن اتمی. فقط drop-in.
- اجرای دوباره امن (idempotent). ‏--dry-run‏ دیف دقیق + دلیل هر تنظیم.
- تغییر ssh/firewall با بازگشت خودکار زمان‌دار؛ لغو فقط با ‏confirm‏ از نشست NEW.
- بدون telemetry. بدون تماس شبکه پنهان.

## شروع سریع

```bash
./optimizer.sh scan --lang fa
./optimizer.sh apply --profile generic --dry-run
./optimizer.sh apply --profile generic --only limits --yes
```

اول همیشه ‏--dry-run‏. برای ssh/firewall یک نشست سالم را باز نگه دارید.
