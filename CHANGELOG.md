# Changelog

All notable changes, newest first. Format: Conventional Commits subjects.

## Unreleased

- Tunnel UI: `sudo srv-tune tunnel` interactive menu (status, keys,
  access, sessions) plus scriptable `tunnel status|keys|access|sessions`;
  non-tty runs print status instead of a menu.
- Tunnel key lifecycle: `keys list|add|remove` with ssh-keygen
  validation, body dedupe, per-change backup, 600 authorized_keys, and
  an audit log for every add/remove.
- Guarded tunnel policy edits: `access set` rewrites only the TUNNEL
  drop-in's policy lines (`--permit-open ...`, `--gateway-ports
  yes|no`), preserves the current port/user, and runs through the ssh
  guard (confirm from a NEW session).
- Tunnel web panel: `sudo srv-tune tunnel web` — loopback-only Python
  stdlib HTTP panel, one-shot token login (HttpOnly cookie + CSRF),
  per-IP login rate limit, read-only sshd policy by design; reach it from
  a workstation with `ssh -L`.
- Tunnel sessions: matches every `Port` in the drop-in (IPv6 included) and
  prints a note to stderr when the drop-in has no `Port` (22 assumed); tests
  pin `PermitTunnel` preservation through `access set`.

## v0.3.0 (2026-10-17)

- repair command: replays the health checks, then re-applies ONLY the
  drifted modules with the profile recorded at apply time (new
  profile=<name> field in applied-changes.log); same rails as apply
  (backup, verify, auto-rollback). Gated modules keep their flags; --dry-run
  prints the diffs and writes nothing; log lines without a profile record
  are refused with guidance (exit 2).
- scan --diff BASELINE.json: fresh read-only scan compared against a scan
  JSON saved earlier with --json; prints only the changed/added/removed
  keys plus the score and profile delta. Baseline missing or not flat
  scan JSON: exit 2. --json still writes the fresh scan as the next
  baseline.
- health command: read-only drift check that replays the applied modules'
  post-apply checks and reports pending unconfirmed guards; --json report.
- Data hardening: kind/tier/verified schema for data lists, fail-closed
  verified-only gate, DNS default/optional tiers with --dns-extra disclosure,
  official-default origins never auto-selected, DATA-REVIEW checklist.
- Shell completion (completion/srv-tune.bash) and man page (docs/srv-tune.1),
  both shipped by install.sh.

- P5: benchmark/compare, installer with checksum gates, verified update,
  uninstall, release workflow, docs set.
- P4: profiles UX, --with-ssh/--with-firewall opt-in with typed
  confirmation, --config custom profiles, i18n fa/en parity.
- P3b: ssh/firewall/fail2ban modules with guard wiring (EXPERIMENTAL).
- P3a: limits/network/kernel/dns/mirror modules with failure injection.
- P2: safety engine (backup/rollback/guard/dry-run/preflight/health).
- P1: read-only scanner with score and recommended profile.
- P0: scaffolding, lib, CI harnesses.
