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

## Tunnel web panel

`sudo srv-tune tunnel web` runs a small Python-stdlib HTTP server as root
on `127.0.0.1:8787` by default. It authenticates with a one-shot token URL
(token file `/var/lib/srv-tune/web/token`, mode 600) that sets an HttpOnly
`SameSite=Strict` cookie; every mutation is POST with a CSRF value, and
five failed logins per IP per minute return 429. The panel shows status,
sessions and keys and can add/remove tunnel keys — it does **not** edit
sshd policy by design. Recommended access is
`ssh -L 8787:127.0.0.1:8787 user@host`; binding another address prints a
warning and should be treated as exposing the panel.
