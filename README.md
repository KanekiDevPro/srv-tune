<div align="center">

# 🛠️ temper

**A Linux server optimizer that shows its work — every change is backed up, verified, and auto-reverted if it breaks.**

[![CI](https://github.com/KanekiDevPro/temper/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/KanekiDevPro/temper/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/KanekiDevPro/temper?sort=semver)](https://github.com/KanekiDevPro/temper/releases)
[![License: MIT](https://img.shields.io/github/license/KanekiDevPro/temper)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-E95420?logo=ubuntu&logoColor=white)](#)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](#)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

[English](README.md) · [فارسی](README.fa.md)

</div>

**Temper** (formerly **srv-tune**): the rename ships with v0.5.0 and has no migration —
on hosts that ran the old name, remove the old drop-ins (`00-srv-tune*.conf`) and the
old state tree (`/var/lib/srv-tune`) by hand.

```text
SCAN → RECOMMEND → APPLY → VERIFY → ROLLBACK-IF-BROKEN
```

<!-- Demo GIF: record `temper scan` + `apply --dry-run` on a fresh VM,
save it as docs/demo.gif, then restore the embed here. -->

## ✨ Why temper

Most "server optimizer" scripts paste sysctl values from the internet and hope. temper computes values from your machine, prints every diff **with a reason**, backs up every file, verifies the result, and arms a timed auto-revert for the risky parts.

- **Read-only first.** `scan` never writes. `apply --dry-run` shows the exact diff before anything changes.
- **Reversible by design.** Every applied change has a backup and a one-command rollback.
- **No lockouts.** ssh/firewall changes auto-revert unless confirmed from a **new** session.
- **No telemetry.** No hidden network calls. Benchmarks print every host they contact.

## 🚀 Install

Requirements: `bash`, root for `apply`/`repair`, a systemd-based Ubuntu/Debian. The installer only copies files — it never applies tuning and never touches services.

**One line** (needs `git`):

```bash
git clone --depth 1 https://github.com/KanekiDevPro/temper.git && sudo ./temper/install.sh --yes
```

**Manual** (recommended the first time — read before you run):

```bash
git clone https://github.com/KanekiDevPro/temper.git
less temper/install.sh
sudo ./temper/install.sh --yes --prefix /usr/local
```

**Pinned release** (verified against the release checksum):

```bash
# take <sum> from sha256sums.txt in the release assets
sudo ./temper/install.sh --tag vX.Y.Z --sha256 <sum> --yes
```

`update` re-verifies checksums; `uninstall` removes program files only — your configs stay until you roll them back.

## ⚡ Quick start

```bash
temper scan                        # read-only: score + recommended profile
temper scan --json baseline.json   # keep a baseline for drift checks
temper health                      # read-only: drift + pending guards
temper apply --dry-run             # exact diff + why, zero writes
sudo temper apply                  # apply the recommended profile (Enter accepts)
sudo temper repair                 # re-apply only the modules that drifted
temper rollback <id>               # undo one apply (see: list-backups)
temper benchmark --out before
temper benchmark --compare before/bench.json after/bench.json --format md
```

From the source tree, replace `temper` with `./optimizer.sh`. Always start with `--dry-run`. For anything touching ssh or the firewall, keep a proven session open and confirm from a **new** one.

## 🔐 Tunnel UI

For an SSH forwarding server (`vpn-tunnel` profile) everything is in one place:

```bash
sudo temper tunnel          # interactive menu: status, keys, access, sessions
sudo temper tunnel status   # no tty: prints the TUNNEL status instead
sudo temper tunnel keys add < id_ed25519.pub
sudo temper tunnel keys remove --fp SHA256:...
sudo temper tunnel sessions
```

`access set --permit-open host:port --gateway-ports no` rewrites only the
policy lines and runs through the usual guard: confirm it from a **new**
session.

The web panel is optional and loopback-only:

```bash
sudo temper tunnel web      # http://127.0.0.1:8787 + one-shot token URL
ssh -L 8787:127.0.0.1:8787 user@server   # from your workstation
```

The panel shows status/sessions/keys and can add or remove keys; it never
edits sshd policy. It authenticates with a 600-mode token file, requires
POST+CSRF for changes, and rate-limits failed logins. Keys are backed up
and every change is audit-logged.

## 🧩 What it tunes

| Module | Status | Summary |
|---|---|---|
| `limits` | stable | file descriptors and PAM limits (drop-in only) |
| `network` | stable | TCP/sysctl tuning computed from your link |
| `kernel` | stable | swappiness, zram hints, journald cap, time-sync checks |
| `dns` | stable | DNS benchmark + backend choice (systemd-resolved/resolv.conf), optional DoT |
| `mirror` | stable | apt mirror switch; opt-in pip/npm/docker registry mirrors |
| `ssh` | **experimental** | ADMIN hardening / TUNNEL forwarding mode, key gate, guarded port change |
| `firewall` | **experimental** | nft/ufw rules derived from the scan, guarded |
| `fail2ban` | **experimental** | jail drop-in with the session source in `ignoreip` (runs with `--with-firewall`) |

Profiles: `generic` · `web` · `database` · `docker` · `vpn-tunnel` · `low-ram` · `custom`.

Registry mirrors (pip/npm/docker) are **unsigned** — unlike apt — so they are reviewed in [`data/`](data/), never enabled by default, and require `--with-registry` plus a typed confirmation.

## 🛡️ Safety model

- Every modified file is backed up first (`/var/lib/temper/backups/<id>/`); `rollback` restores it.
- Atomic writes: temp → validate (e.g. `sshd -t`) → move. Drop-ins only, sorted first; main configs are never edited.
- Idempotent: re-running `apply` is safe. `health` reports drift, `repair` fixes only what drifted.
- ssh/firewall changes arm an independent timed auto-revert; only `temper confirm <id>` from a **new** session cancels it.
- No telemetry. No hidden network calls.

## 🖥️ Supported systems

| Tier | Systems |
|---|---|
| Tier 1 | Ubuntu 24.04 · Ubuntu 26.04 · Debian 13 |
| Tier 2 | Ubuntu 22.04 · Debian 12 |
| Best effort | Ubuntu 20.04 |

Debian 11 is EOL: the scanner warns and `apply` is blocked. The OS is never upgraded automatically.

## 📚 Documentation

- [docs/TESTING-VM.md](docs/TESTING-VM.md) — read before using the experimental modules
- [docs/DATA-REVIEW.md](docs/DATA-REVIEW.md) — mirror data review rules
- [docs/VERIFICATION-DEBT.md](docs/VERIFICATION-DEBT.md) — exactly what is and is not verified
- [docs/temper.1](docs/temper.1) — man page (`man temper` after install)
- [CHANGELOG.md](CHANGELOG.md) — release history

## ❓ FAQ

**Does `scan` change anything?** No. It is strictly read-only.
**What if I lose SSH after a change?** The timed guard reverts automatically unless you confirm from a new session.
**Is it production-ready?** Core modules are stable; `ssh`/`firewall`/`fail2ban` are experimental — test them on a disposable VM first ([docs/TESTING-VM.md](docs/TESTING-VM.md)).
**Does it phone home?** No telemetry, no background calls.
**Persian?** `--lang fa` for output, plus a full [README.fa.md](README.fa.md).
**Where do backups live?** `/var/lib/temper/backups/` — see `temper list-backups`.

## 🤝 Contributing

- [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [CHANGELOG.md](CHANGELOG.md)
- Bugs and features: use the templates in `.github/ISSUE_TEMPLATE/`.
- Every PR runs shellcheck, shfmt, bats, a scan matrix (Ubuntu/Debian) and real-systemd integration on GitHub Actions.

## 📄 License

MIT — see [LICENSE](LICENSE).
