# Verification debt

Status labels: `CI` (runs on real Linux in CI on every push/PR), `unit-tested
only` (SYSROOT/stubs on any host — never claim more), `VM-verified` (a human
ran it on a disposable VM and recorded logs; only the human marks this).

This file is updated in every PR.

## Module matrix (v0.1.0 frozen scope)

| Area | Status | What CI covers | Manual scenarios remaining |
|---|---|---|---|
| scanner (read-only) | CI | scan-matrix on 5 images × root/non-root + assert-scan (no false `unknown`); bats JSON/score/profile | none (read-only by construction) |
| limits | unit-tested only | bats: computed values, drop-ins, idempotency, dry-run, debug opt-in | apply on a 22.04 + 26.04 VM, verify `ulimit -Hn` after re-login |
| network (sysctl) | unit-tested only | bats: BBR gating, denylist, container skip, BDP caps, dry-run | apply on VM, `sysctl -a` spot-check, reboot persistence of drop-in |
| kernel (swappiness/zram/journald/scheduler/time) | unit-tested only | bats: profile swappiness, journald cap, chrony detect, NTS guard | zram on a <=1GB VM; scheduler rule on NVMe vs HDD; chrony makestep on 26.04 |
| dns | unit-tested only | bats: benchmark parse, backend selection, cloud-init refusal, rollback on broken resolution, drill fallback | live benchmark + apply on VM (systemd-resolved vs resolv.conf), unconfirmed-guard revert of DNS |
| mirror | unit-tested only | bats: swap guard, both apt formats, trust refusal, rollback on failed `apt update` | live mirror switch + `apt update` on 24.04 (deb822) and 12 (one-line) |
| ssh (EXPERIMENTAL) | CI (temp-only) | bats: all modes, key gate, whitelist, port/socket, close-port, crash hook; integration: real `sshd -t -f`, temp daemon on 22222, real-timer revert | TESTING-VM §1/§2/§5/§6 on disposable VM; real reload on socket vs service |
| firewall (EXPERIMENTAL) | CI (temp-only) | bats: ordering, nft scoping vs foreign tables, rollback; integration: real `nft -c` | TESTING-VM §3 incl. reboot persistence (human-only); real `ufw enable` |
| fail2ban (EXPERIMENTAL) | CI (temp-only) | bats: ignoreip incl. session source, backend=systemd | TESTING-VM §4 (real ban of external IP, session never banned) |
| backup/rollback/guard/dry-run/preflight/health | CI | bats incl. signals, partial failure, TEST-only fallback; integration: real systemd-run timers (kill -9, cancel, same-session reject) | guard expiry timing on a loaded VM (cosmetic) |
| benchmark/installer/update | CI | bats incl. checksum gates (file:// paths run on Linux; skipped where host curl lacks it) | real release download on version bump |
| profiles/UX/i18n | CI (mostly) | bats: mapping, gating, typed phrases, i18n parity, custom config | whiptail interactive path (runners lack whiptail: plain path only) — unit-tested only |
| release workflow | UNTESTED | none (no tag ever pushed; tagging is maintainer-only) | first release is a manual, watched procedure |
| uutils coreutils / sudo-rs (26.04) | CI | uutils-check job: full bats + scanner smoke on ubuntu:26.04; flavors recorded | none outstanding |

## Round 2 data hardening (open)

Entries leave only with fresh evidence (CI link or manual-review signature),
never by assertion.

- [ ] DATA-REVIEW rows: 16 of 17 flipped to `verified=true` per maintainer
  review 2026-10-16 (memory-written owner/docs accepted by the reviewer).
  Row 6 (185.51.200.2 conflict) stays pending until the operator is
  attributed. Release gate passes only when zero entries are pending.
- [ ] 185.51.200.2 ownership conflict: RESOLVED 2026-10-16 by maintainer
  decision — disputed entry deleted outright instead of attributed
  (was `electrotm`, third-party README said Shecan secondary).
- [ ] `release.yml` pending-gate never fired on a real tag push (runs only on
  `v*.*.*`). Next release attempt will exercise it (expected FAIL while
  entries are pending — that is the gate working).
- [ ] `tests/pre-publish.sh` also reports pre-existing environment findings
  unrelated to this branch (secret-like content in tree, key material in
  history, local username in paths). Triage separately; do NOT weaken the
  `verified=pending` gate to silence them.
- [ ] Full `bats tests/` suite times out on Windows dev hosts; Linux CI is
  the source of truth (`lint-test` + `uutils-check` jobs).
- [ ] DoT offer path and netplan apply path in `modules/dns.sh` are covered
  where tests reach them (DoT probe + recommend offer, `--with-dot`
  fail-closed on resolved backend only, netplan backend test — all on this
  branch); dedicated VM-level DoT/netplan runs remain human-only. Pending
  this branch's merge.

## Manual scenario tracker (TESTING-VM.md)

| Scenario | Status | Log location when done |
|---|---|---|
| §0 prepare (scan/audit) | open | `docs/vm-logs/<os>-<date>/00-prepare.log` |
| §1 ssh.socket vs ssh.service | open | `.../01-socket-service.log` |
| §2 port change + unconfirmed revert + close-22 | open | `.../02-port-guard.log` |
| §3 firewall + reboot persistence | open (reboot part human-only) | `.../03-firewall.log` |
| §4 fail2ban ignoreip + external ban | open | `.../04-fail2ban.log` |
| §5 TUNNEL restrictions | open | `.../05-tunnel.log` |
| §6 crash between write and validate | open (scripted in `tests/vm/p3b-systemd.sh`) | `.../06-crash.log` |

Harness: `tests/vm/run-all.sh <ssh-alias> <os>` (refuses localhost; needs a
snapshot-restore hook for destructive scenarios; stops on SSH loss).
Per-scenario scripts live next to it (`smoke-*.sh`) with shared helpers in
`tests/vm/smoke-lib.sh`.
