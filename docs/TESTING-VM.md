# Manual smoke checklist for a disposable VM (unit tests are NOT proof here)

Everything below runs on a THROWAWAY VM (Ubuntu 24.04 and Debian 13) with
console access (the provider console, not SSH alone). Snapshot first. Every
step that changes SSH must keep one proven session open until the new path
is confirmed from a NEW session.

Status labels used in reports: `vm-verified` (did it on a real VM) vs
`unit-tested only` (SYSROOT/stubs — never claim more).

## 0. Prepare

```bash
git clone <repo> /tmp/temper && cd /tmp/temper
./optimizer.sh scan --lang en
./optimizer.sh audit
```

Record: OS/tier, INIT (systemd?), VIRT, CC/qdisc, DNS backend, apt format.

## 1. ssh.socket vs ssh.service

```bash
systemctl list-sockets | grep -i ssh || true
systemctl is-active ssh.socket ssh.service || true
```

- Ubuntu 24.04: expect `ssh.socket` active (socket activation). Reloads go
  through the socket unit; verify with `ss -tlnp | grep :22`.
- Debian 13: expect `ssh.service` active, socket inactive. Reloads go
  through `ssh.service`.
- Apply: `optimizer apply --profile generic --only ssh --dry-run` first
  (diff + reasons, no changes), then without `--dry-run --yes`.
- Confirm `00-temper.conf` exists in `/etc/ssh/sshd_config.d/` and sorts
  first (`ls`). `sshd -t` must pass. Main `sshd_config` must be UNTOUCHED
  (`git diff` equivalent: compare mtime/content before/after).

## 2. Port change + unconfirmed-guard revert

```bash
TEMPER_SSH_PORT=2222 optimizer apply --profile generic --only ssh --yes
# guard prints: temper confirm <id>
ss -tlnp | grep 2222   # must listen; port 22 must ALSO still listen
sleep 310              # let the guard expire WITHOUT confirming
ss -tlnp | grep 2222   # must be GONE (auto-revert fired)
cat /etc/ssh/sshd_config.d/00-temper.conf  # original content back
```

Then redo, connect on 2222 from a NEW session, run
`temper confirm <id>` THERE, and only then close the old port:

```bash
optimizer ssh-close-port 22   # refuses unless 2222 listens right now
```

## 3. Firewall persistence after reboot

- ufw path: `ufw status numbered` shows the ssh allow BEFORE `enable`;
  `/etc/default/ufw` has `IPV6=yes`. Reboot, then `ufw status` is still
  active (ufw persists itself).
- nft path: `nft list ruleset` shows ONLY `table inet temper` added;
  pre-existing tables (e.g. Docker's) are untouched. Reboot: the operator
  must load `/etc/nftables.d/00-temper.nft` at boot (printed note) —
  verify rules return after reboot, or record that persistence is manual.
- Docker warning: with Docker installed, `scan`/`audit` must print the
  "published ports bypass ufw" warning; verify a published test port is
  reachable despite ufw (documents the bypass, then remove the container).

## 4. fail2ban (ignoreip works, outsiders banned)

- `cat /etc/fail2ban/jail.d/00-temper.local`: `ignoreip` contains YOUR
  session source address and `backend = systemd`.
- From an EXTERNAL host (not the session IP): fail 6+ logins with a bad
  password, then `fail2ban-client status sshd` shows a ban for that IP.
- Your session IP must NEVER appear in the ban list.

## 5. TUNNEL restrictions (vpn-tunnel profile only)

```bash
optimizer apply --profile vpn-tunnel --dry-run   # review: TUNNEL mode
```

- `Match User tunnel` block has `PermitTTY no`,
  `ForceCommand /usr/sbin/nologin`, explicit `PermitOpen`.
- `GatewayPorts` stays `no` unless explicitly requested.
- `PermitTunnel`/`ip_forward` appear ONLY with tun mode in this profile.
- Client snippet + autossh unit are generated under
  `/var/lib/temper/` (copy, never auto-installed).

## 6. Crash between write and validate

Covered automatically by `tests/vm/p3b-systemd.sh` (kill -9 at the exact
point, real timer reverts). Manually: set a 10s guard, start apply, `kill
-9` the optimizer PID mid-run, wait, confirm the original files are back.

## 7. Tunnel UI

```bash
sudo ./optimizer.sh tunnel                # interactive menu (TUI)
sudo ./optimizer.sh tunnel keys add < client.pub
sudo ./optimizer.sh tunnel keys list --json
```

- TUI key add through the real tunnel user: from a NEW session
  `ssh -p <port> tunnel@<vm>` must get `PermitTTY no`/nologin (no shell),
  while a forwarding-only command (`ssh -L 8080:127.0.0.1:80 tunnel@<vm>`)
  works.
- Panel over the tunnel: run `sudo ./optimizer.sh tunnel web` on the VM,
  then from the workstation `ssh -L 8787:127.0.0.1:8787 user@vm` and open
  the printed token URL in a REAL browser: status, sessions, and keys must
  render, and adding then removing a key must work. A `curl` attempt from
  outside the VM must NOT reach 8787.
- Remove the LAST key through the panel (or `keys remove --fp`): the
  already-authenticated session keeps working, a NEW login fails.
- `access set --permit-open db:5432 --gateway-ports no` (typed confirm),
  then confirm the guard from a NEW session and verify `sshd -T` shows the
  new PermitOpen.

## 8. What NOT to do on the VM

Never `ufw --force reset`, `iptables -F`, `nft flush ruleset`, or edit
`/etc/ssh/sshd_config` directly. The hygiene gate (`tests/hygiene.sh`)
fails the build on all of these.
