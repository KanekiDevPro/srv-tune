# Security policy

## Reporting

Email the maintainer privately (see `git log` for the contact) with:
what you ran, the OS/version, relevant logs (redact hostnames/keys), and
whether a guard/rollback was involved. Do NOT open a public issue for a
suspected vulnerability. Expect an acknowledgment within 7 days.

## Scope notes

- srv-tune only writes drop-in configs under testable paths, backs up
  everything first, and never exfiltrates data (no telemetry by design).
- The EXPERIMENTAL modules (ssh/firewall/fail2ban) require explicit flags
  plus typed confirmation plus NEW-session confirm for exactly this reason.
- If a guard ever fails to revert, that is treated as a P0 bug: report it
  with the guard id, `applied-changes.log`, and the manifest.
