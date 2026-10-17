# srv-tune — Linux server optimizer

SCAN -> RECOMMEND -> APPLY -> VERIFY -> ROLLBACK-IF-BROKEN.

<!-- Demo GIF: record `optimizer scan` + `apply --dry-run` on a fresh VM,
save it as docs/demo.gif, then restore the embed here. -->

Read this in Persian: [README.fa.md](README.fa.md).

## Scope (honest)

- Core modules = **stable**: `limits`, `network` (sysctl), `kernel`
  (resources/time), `dns`, `mirror` (apt + `pip_mirror`, `npm_mirror`,
  `docker_mirror` registry mirrors, tool-gated). Registry mirrors are NOT
  signed like apt: review owner/docs in `data/` before use.
- `ssh`, `firewall`, `fail2ban` = **EXPERIMENTAL**: they require explicit
  flags (`--with-ssh` / `--with-firewall`) plus an interactively typed
  confirmation, and every change is guarded with timed auto-revert. Do not
  use them without reading [docs/TESTING-VM.md](docs/TESTING-VM.md).

## Supported OS

| Tier | Systems |
|---|---|
| Tier 1 | Ubuntu 24.04, Ubuntu 26.04, Debian 13 |
| Tier 2 | Ubuntu 22.04, Debian 12 |
| Best-effort | Ubuntu 20.04 |

Debian 11 is EOL: the scanner warns and apply is blocked. The OS is never
auto-upgraded.

## Safety model

- Every file is backed up before change (manifest in
  `/var/lib/srv-tune/backups/<id>/`); `rollback [id]` restores.
- Atomic writes (temp -> validate -> move). Drop-ins only, never main
  configs (`00-srv-tune.*` sorts first; sshd is first-match-wins).
- Idempotent re-runs. `--dry-run` shows the exact diff plus the reason
  (`why`) for every setting; values are computed from the scan, never
  magic numbers.
- Every ssh/firewall change arms an independent timed auto-revert that only
  `srv-tune confirm <id>` from a NEW session cancels.
- No telemetry. No hidden network calls (benchmarks print every host they
  contact; `iperf3` runs only with `--iperf-server`).

## Quick start

```bash
./optimizer.sh scan                     # read-only report + JSON + score
./optimizer.sh scan --diff before.json  # drift vs a scan saved with --json
./optimizer.sh health                   # read-only: drift check + pending guards
./optimizer.sh repair                   # re-apply modules that drifted (asks first)
./optimizer.sh apply                    # recommended profile (Enter accepts)
./optimizer.sh apply --profile web --dry-run
./optimizer.sh apply --profile generic --only limits --yes
./optimizer.sh apply --profile vpn-tunnel --with-ssh   # EXPERIMENTAL path
./optimizer.sh rollback <id> | ./optimizer.sh list-backups
./optimizer.sh benchmark --out before && ./optimizer.sh benchmark --compare before/bench.json after/bench.json --format md
```

Always run `--dry-run` first. Keep one proven session open for anything
touching ssh/firewall, and confirm from a NEW session.

## Install

```bash
# Read the script first, then:
./install.sh --yes --prefix /usr/local
# Pinned release:
./install.sh --tag v0.3.0 --sha256 <sum> --yes
```

`update` re-verifies checksums; `uninstall` removes program files only
(your configs stay until you roll them back).

## Contribute / security / changes

- [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
  [CHANGELOG.md](CHANGELOG.md), [LICENSE](LICENSE) (MIT).
- Issues: use the templates in `.github/ISSUE_TEMPLATE/`.
