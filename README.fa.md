<div align="center">

# 🛠️ srv-tune

**بهینه‌ساز سرور لینوکس که کارش را نشان می‌دهد — هر تغییر بکاپ می‌شود، ارزیابی می‌شود و اگر خراب کند، خودکار برمی‌گردد.**

[![CI](https://github.com/KanekiDevPro/srv-tune/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/KanekiDevPro/srv-tune/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/KanekiDevPro/srv-tune?sort=semver)](https://github.com/KanekiDevPro/srv-tune/releases)
[![License: MIT](https://img.shields.io/github/license/KanekiDevPro/srv-tune)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-E95420?logo=ubuntu&logoColor=white)](#)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](#)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

[English](README.md) · **فارسی**

</div>

```text
SCAN → RECOMMEND → APPLY → VERIFY → ROLLBACK-IF-BROKEN
```

<!-- GIF نمایشی: خروجی `srv-tune scan` و `apply --dry-run` را روی VM تمیز ضبط کنید،
در docs/demo.gif ذخیره کنید و embed را اینجا برگردانید. -->

## ✨ چرا srv-tune؟

بیشتر اسکریپت‌های «بهینه‌سازی سرور» چند مقدار sysctl را از اینترنت کپی می‌کنند و امیدوارند. srv-tune مقدارها را از خودِ ماشین حساب می‌کند، هر دیف را **با دلیل** نشان می‌دهد، قبل از هر تغییر بکاپ می‌گیرد، نتیجه را verify می‌کند و برای بخش‌های پرخطر یک بازگشت خودکار زمان‌دار مسلح می‌کند.

- **اول فقط خواندن.** `scan` هیچ‌چیز نمی‌نویسد؛ `apply --dry-run` دیف دقیق را قبل از هر تغییری نشان می‌دهد.
- **برگشت‌پذیر.** هر تغییر بکاپ دارد و با یک دستور برمی‌گردد.
- **بدون قفل‌شدن.** تغییرهای ssh/فایروال خودکار برمی‌گردند، مگر اینکه از یک نشست **جدید** تایید کنید.
- **بدون تلمتری.** بدون تماس شبکه پنهان؛ بنچمارک همه هاست‌هایی را که لمس می‌کند چاپ می‌کند.

## 🚀 نصب

پیش‌نیازها: `bash`، دسترسی root برای `apply`/`repair`، سیستم systemd روی Ubuntu/Debian. نصب‌کننده فقط فایل کپی می‌کند — هیچ تنظیمی اعمال نمی‌کند و به سرویس‌ها دست نمی‌زند.

**تک‌خطی** (ریپوی عمومی، نیاز به `git`):

```bash
git clone --depth 1 https://github.com/KanekiDevPro/srv-tune.git && sudo ./srv-tune/install.sh --yes
```

**دستی** (برای بار اول توصیه می‌شود — قبل از اجرا بخوانید):

```bash
git clone https://github.com/KanekiDevPro/srv-tune.git
less srv-tune/install.sh
sudo ./srv-tune/install.sh --yes --prefix /usr/local
```

**ریلیز پین‌شده** (تاییدشده با چک‌سام ریلیز):

```bash
# مقدار <sum> را از sha256sums.txt در asset های ریلیز بردارید
sudo ./srv-tune/install.sh --tag vX.Y.Z --sha256 <sum> --yes
```

`update` چک‌سام‌ها را دوباره تایید می‌کند؛ `uninstall` فقط فایل‌های برنامه را حذف می‌کند — کانفیگ‌های شما تا رول‌بک باقی می‌مانند.

## ⚡ شروع سریع

```bash
srv-tune scan                        # فقط خواندن: امتیاز + پروفایل پیشنهادی
srv-tune scan --json baseline.json   # نگه‌داشتن بیس‌لاین برای drift
srv-tune health                      # فقط خواندن: drift + گاردهای در انتظار
srv-tune apply --dry-run             # دیف دقیق + دلیل، بدون نوشتن
sudo srv-tune apply                  # اعمال پروفایل پیشنهادی (Enter قبول)
sudo srv-tune repair                 # فقط ماژول‌های drifted را دوباره اعمال می‌کند
srv-tune rollback <id>               # برگشت یک اعمال (لیست: list-backups)
srv-tune benchmark --out before
srv-tune benchmark --compare before/bench.json after/bench.json --format md
```

از داخل سورس، به‌جای `srv-tune` از `./optimizer.sh` استفاده کنید. همیشه با `--dry-run` شروع کنید. برای ssh/فایروال یک نشست سالم باز نگه دارید و از نشست **جدید** تایید کنید.

## 🔐 رابط تونل

برای سرور فوروارد SSH (پروفایل `vpn-tunnel`) همه‌چیز در یک جا است:

```bash
sudo srv-tune tunnel          # منوی تعاملی: وضعیت، کلیدها، دسترسی، نشست‌ها
sudo srv-tune tunnel status   # بدون tty: به‌جای منو وضعیت TUNNEL را چاپ می‌کند
sudo srv-tune tunnel keys add < id_ed25519.pub
sudo srv-tune tunnel keys remove --fp SHA256:...
sudo srv-tune tunnel sessions
```

`access set --permit-open host:port --gateway-ports no` فقط خط‌های سیاست را
بازنویسی می‌کند و از همان گارد عبور می‌کند: از نشست **جدید** تایید کنید.

پنل وب اختیاری است و فقط روی loopback گوش می‌دهد:

```bash
sudo srv-tune tunnel web      # http://127.0.0.1:8787 + URL توکن یک‌بارمصرف
ssh -L 8787:127.0.0.1:8787 user@server   # از ورک‌استیشن خودتان
```

پنل وضعیت/نشست‌ها/کلیدها را نشان می‌دهد و می‌تواند کلید اضافه یا حذف کند؛
هرگز سیاست sshd را تغییر نمی‌دهد. با فایل توکن با مجوز 600 احراز هویت
می‌کند، برای تغییرات POST+CSRF می‌خواهد و ورودهای ناموفق را محدود می‌کند.
کلیدها بکاپ می‌شوند و هر تغییر در audit log ثبت می‌شود.

## 🧩 چه چیزهایی را تنظیم می‌کند

| ماژول | وضعیت | خلاصه |
|---|---|---|
| `limits` | پایدار | file descriptor و PAM limits (فقط drop-in) |
| `network` | پایدار | تنظیم TCP/sysctl بر اساس لینک شما |
| `kernel` | پایدار | swappiness، اشاره‌های zram، سقف journald، بررسی همگام‌سازی زمان |
| `dns` | پایدار | بنچمارک DNS + انتخاب بک‌اند (systemd-resolved/resolv.conf)، DoT اختیاری |
| `mirror` | پایدار | تغییر میرور apt؛ میرورهای pip/npm/docker اختیاری |
| `ssh` | **آزمایشی** | حالت ADMIN / TUNNEL، گیت کلید، تغییر پورت زیر گارد |
| `firewall` | **آزمایشی** | قواعد nft/ufw از روی اسکن، زیر گارد |
| `fail2ban` | **آزمایشی** | drop-in جیل با سورس نشست در `ignoreip` (با `--with-firewall`) |

پروفایل‌ها: `generic` · `web` · `database` · `docker` · `vpn-tunnel` · `low-ram` · `custom`.

میرورهای رجیستری (pip/npm/docker) برخلاف apt **امضا ندارند** — در [`data/`](data/) بازبینی شده‌اند، هرگز پیش‌فرض نیستند و به `--with-registry` + تایید تایپی نیاز دارند.

## 🛡️ مدل امنیت

- هر فایل قبل تغییر بکاپ می‌شود (`/var/lib/srv-tune/backups/<id>/`)؛ `rollback` برمی‌گرداند.
- نوشتن اتمی: temp → اعتبارسنجی (مثلاً `sshd -t`) → move. فقط drop-in، اول sort می‌شود؛ کانفیگ اصلی هرگز ویرایش نمی‌شود.
- ایدمپوتنت: اجرای دوباره امن است. `health` دریفت را گزارش می‌دهد، `repair` فقط drifted را درست می‌کند.
- تغییر ssh/فایروال یک بازگشت خودکار زمان‌دار مستقل مسلح می‌کند؛ فقط `srv-tune confirm <id>` از نشست **جدید** لغوش می‌کند.
- بدون تلمتری و بدون تماس شبکه پنهان.

## 🖥️ سیستم‌های پشتیبانی‌شده

| سطح | سیستم‌ها |
|---|---|
| Tier 1 | Ubuntu 24.04 · Ubuntu 26.04 · Debian 13 |
| Tier 2 | Ubuntu 22.04 · Debian 12 |
| بهترین تلاش | Ubuntu 20.04 |

Debian 11 منقضی است: اسکنر هشدار می‌دهد و `apply` بلاک می‌شود. سیستم‌عامل هرگز خودکار ارتقا نمی‌یابد.

## 📚 مستندات

- [docs/TESTING-VM.md](docs/TESTING-VM.md) — قبل از ماژول‌های آزمایشی بخوانید
- [docs/DATA-REVIEW.md](docs/DATA-REVIEW.md) — قواعد بازبینی داده میرورها
- [docs/VERIFICATION-DEBT.md](docs/VERIFICATION-DEBT.md) — دقیقاً چه چیزی تأیید شده و چه چیزی نه
- [docs/srv-tune.1](docs/srv-tune.1) — man page (`man srv-tune` بعد نصب)
- [CHANGELOG.md](CHANGELOG.md) — تاریخچه ریلیزها

## ❓ سؤال‌های رایج

**آیا `scan` چیزی را تغییر می‌دهد؟** نه؛ کاملاً فقط‌خواندنی است.
**اگر بعد از تغییر SSH را از دست بدهم؟** گارد زمان‌دار خودکار برمی‌گرداند، مگر از نشست جدید تایید کنید.
**برای پروداکشن آماده است؟** ماژول‌های اصلی پایدارند؛ `ssh`/`firewall`/`fail2ban` آزمایشی‌اند — اول روی VM یک‌بارمصرف تست کنید ([docs/TESTING-VM.md](docs/TESTING-VM.md)).
**تلمتری دارد؟** نه.
**فارسی؟** `--lang fa` برای خروجی، و [README.fa.md](README.fa.md) کامل.
**بکاپ‌ها کجا هستند؟** `/var/lib/srv-tune/backups/` — `srv-tune list-backups`.

## 🤝 مشارکت

- [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CHANGELOG.md](CHANGELOG.md)
- باگ/فیچر: از تمپلیت‌های `.github/ISSUE_TEMPLATE/` استفاده کنید.
- هر PR روی GitHub Actions: shellcheck، shfmt، bats، ماتریس اسکن (Ubuntu/Debian) و integration واقعی systemd اجرا می‌شود.

## 📄 لایسنس

MIT — [LICENSE](LICENSE).
