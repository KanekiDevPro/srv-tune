# Changelog

All notable changes, newest first. Format: Conventional Commits subjects.

## Unreleased

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
