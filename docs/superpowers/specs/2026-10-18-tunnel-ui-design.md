# srv-tune tunnel UI — design spec

Status: draft for review
Date: 2026-10-18
Scope: `vpn-tunnel` profile operators (SSH forwarding servers)

## Problem

Operators who run the `vpn-tunnel` profile (sshd as a forwarding server:
TUNNEL mode, dedicated `tunnel` user, `PermitOpen`, `GatewayPorts`,
optional tun forwarding) must inspect and edit drop-ins and
`authorized_keys` by hand. They want an easy, safe way to see tunnel state,
manage client keys, and adjust forwarding policy — in the terminal (TUI) or
in a browser (panel) — without weakening the existing lockout guards.

## Goals

- One core implementation in `lib/tunnel.sh`; the TUI and the web panel are
  thin frontends over the same behavior.
- Status: mode, port, tunnel user, `PermitOpen`, `GatewayPorts`,
  `PermitTunnel`, `ip_forward`, drop-in presence, active sessions.
- Keys: list / add / remove for the tunnel user, with backup, validation,
  dedupe, correct permissions, and an audit log.
- Access policy (`PermitOpen`, `GatewayPorts`): same apply rails as the ssh
  module — backup, atomic write, `sshd -t`, reload, verify, timed
  auto-revert; confirmation only via `srv-tune confirm <id>` from a NEW
  session.
- Web panel: loopback-bound, token auth, dashboard + key management.
- TUI: zero new runtime dependencies. Panel: python3 stdlib only, optional.

## Non-goals (v1)

- Multi-user tunnel farms or per-user quotas (module today has one user).
- systemd unit / daemonization for the panel (foreground, Ctrl+C stops it).
- TLS, multiple admins, remote bind by default.
- Changing sshd policy from the web panel (see Security).

## Architecture

```
srv-tune tunnel [status|keys|access|sessions|web]
        |
        +-- lib/tunnel.sh        all logic + safety rails (bash)
        |
        +-- web/tunnel_web.py    HTTP frontend (python3 stdlib only)
                                   calls the CLI with --json; never
                                   re-implements tunnel logic
```

The web server is a subprocess client of the installed CLI
(`srv-tune tunnel ... --json`), so both frontends exercise exactly the same
code path and tests.

## State and files

| What | Where | Notes |
|---|---|---|
| Tunnel user keys | `~tunnel/.ssh/authorized_keys` | dir `0700`, file `0600`, owner `tunnel` |
| Key backups | `/var/lib/srv-tune/backups/keys-<utc>/` | `authorized_keys` + `manifest.tsv` (reuse backup patterns) |
| Audit log | `/var/lib/srv-tune/tunnel-actions.log` | append-only, one line per mutation |
| Web token | `/var/lib/srv-tune/web/token` | 32 hex chars, `0600`, created on first `tunnel web` |

Audit line format:

```
ts=<ISO-8601> actor=tui|web action=key-add fp=SHA256:... comment="..." src=<ip|tty> result=ok|fail
```

## CLI contract

```
srv-tune tunnel                     # TUI (non-tty: prints status, exit 0)
srv-tune tunnel status [--json]
srv-tune tunnel keys list [--json]
srv-tune tunnel keys add [--file PATH|-] [--comment TEXT]
srv-tune tunnel keys remove --fp SHA256:...
srv-tune tunnel access show [--json]
srv-tune tunnel access set --permit-open LIST --gateway-ports yes|no
srv-tune tunnel sessions [--json]
srv-tune tunnel web [--port 8787] [--bind 127.0.0.1]
```

- `keys add` reads the public key from `--file` or stdin (stdin keeps key
  material out of `ps` output). `--comment` replaces the trailing comment
  on the stored line.
- `access set` requires both flags (a full policy in one command); current
  values come from `access show`. `--permit-open` takes a comma-separated
  list in sshd syntax (`host:port[,host:port]`), or `none` to disable
  forwarding targets. It goes through the existing ssh apply rails and
  prints the guard id; cancel with `srv-tune confirm <id>` from a NEW
  session.
- Root: `keys` and `access set` require root. `status`, `sessions` and
  `access show` are best-effort unprivileged and print a note when a value
  is not readable.
- `sessions` reports established TCP connections to the ssh port
  (`ss -tnp`) with the remote endpoint and owning sshd PIDs; no journal
  parsing in v1 (journal text formats drift between distros).
- Exit codes: `0` ok, `1` runtime failure, `2` usage/precondition
  (not root where required, tunnel user missing, python3 missing for web,
  unsafe bind without explicit flag).

## Safety model

### Keys
- Root required.
- Each added line must parse as an OpenSSH public key
  (`ssh-keygen -l -f -`); options on the line are allowed and preserved.
- Dedupe by key body; `remove` takes the `SHA256:` fingerprint.
- Atomic replace: write temp in the same dir, `chown tunnel`, `chmod 600`,
  rename. Keep one backup per mutation.
- No sshd reload needed — authorized_keys is read per authentication.

### sshd policy
- Render the tunnel drop-in via the existing `ssh_render_tunnel` with
  `SRV_TUNE_PERMIT_OPEN` / `SRV_TUNE_TUNNEL_GATEWAY` overrides.
- Backup → atomic write → `sshd -t` → reload → verify (daemon up, port
  listening) → `guard_start` (timed auto-revert, NEW-session confirm).
- Main configs are never edited; drop-in only.

### Web panel
- Default bind `127.0.0.1`; any other bind requires `--bind` and prints a
  warning. Recommended access: `ssh -L 8787:127.0.0.1:8787 user@server`.
- Auth: random 32-hex token stored `0600`; login URL printed once at start
  (`/?token=...`), exchanged for an `HttpOnly; SameSite=Strict` cookie; the
  token value is an HMAC key, not stored in the cookie verbatim.
- Constant-time comparison; 5 failed auth attempts per minute per IP →
  `429`.
- All mutations are POST + CSRF: they require an `X-CSRF` header whose
  value is derived from the signed cookie and embedded in the page; GET
  never changes state. `SameSite=Strict` is defense in depth.
- **Policy changes are deliberately absent from the panel.** The guard's
  new-session confirmation is a human-in-an-SSH-shell step; a web page must
  not be able to confirm a change that could lock the operator out.
- The panel calls `$SRV_TUNE_BIN` when set, otherwise `srv-tune` from
  `PATH`, always with `--json`.
- The panel runs as root (it must chown keys to the tunnel user) and stays
  in the foreground; `Referrer-Policy: no-referrer`, no external assets.

## TUI

- Dashboard: one screen, same fields as `status --json`.
- Menu (existing `ui_menu` / `ui_confirm` helpers): refresh, keys, access,
  sessions, quit. Language via existing `--lang fa|en`.
- All actions map 1:1 to the CLI subcommands (no logic in the menu layer).

## Web panel

- Single file `web/tunnel_web.py` (stdlib: `http.server`, `hmac`,
  `secrets`, `json`, `subprocess`).
- Endpoints:

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | dashboard (server-rendered HTML, meta refresh 10s) |
| GET | `/api/status` | tunnel status JSON |
| GET | `/api/sessions` | sessions JSON |
| GET | `/api/keys` | keys JSON |
| POST | `/api/keys/add` | `{key, comment}` |
| POST | `/api/keys/remove` | `{fp}` |

- UI strings: small `en`/`fa` dictionary selected by `?lang=` / cookie.
- Errors: `{"ok":false,"error":"..."}` with proper status codes; no stack
  traces or key material in responses.
- Refuses to start if the token file is group/world-readable.

## Testing

- `tests/test_tunnel.bats`: status render from fixtures; key add/remove,
  dedupe, invalid key, permissions; access render + guard arming under
  `SRV_TUNE_TEST` paths; non-tty behavior; exit codes.
- `tests/test_tunnel_web.bats`: server on a random port with a stub CLI —
  401 without cookie, login flow, CSRF enforcement, keys add/remove
  round-trip, non-loopback bind refused without `--bind`, token-perm check.
- `tests/vm/tunnel-systemd.sh` (CI integration): real `sshd -t` on a temp
  drop-in + reload/guard smoke, temp files only.
- CI: existing bats job runs the new tests; add a web smoke step
  (python3 is present on the runners) plus `python3 -m py_compile`.
- shellcheck + shfmt for bash; man/completion tests extended.

## Docs and debt

- `docs/srv-tune.1`: tunnel section and options.
- `completion/srv-tune.bash`: subcommands and flags.
- `CHANGELOG.md`: Unreleased entry.
- `docs/VERIFICATION-DEBT.md`: new row for the tunnel UI with truthful
  status (unit + integration in CI; real-VM matrix entry until exercised).
- `README.md` / `README.fa.md`: "Tunnel UI" section (TUI, panel, SSH-forward
  access, security model).
- `SECURITY.md`: panel model (root, loopback, token).

## Risks

- A root-owned HTTP server is a real attack surface; mitigated by loopback
  bind, token auth, rate limiting, minimal endpoints and read-only policy.
- python3 may be absent on minimal systems: only the panel is unavailable;
  TUI keeps working and prints a clear error.
- authorized_keys edited manually while the panel runs: last writer wins;
  the backup + audit line makes the previous state recoverable.
- `sshd` reload behavior is inherited from the ssh module (guarded,
  verified); no new reload path is introduced.

## Rollout

- Single PR; new commands only, no behavior change for existing flows.
- Ships in the next release; no feature flag needed.
