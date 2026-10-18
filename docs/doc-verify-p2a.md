# P2a: doc verification results (official sources)

Checked before writing any P2 safety-engine code. Anything still open is
marked OPEN and has a VM gate in CI (`tests/vm/`).

## 1. sshd first-match-wins — CONFIRMED

Source: OpenBSD `sshd_config(5)` (upstream authority, man.openbsd.org):
"Unless noted otherwise, for each keyword, the first obtained value
will be used." `Match` blocks: "If a keyword appears in multiple Match
blocks that are satisfied, only the first instance of the keyword is
applied." `Include` globs expand in lexical order; relative paths resolve
under `/etc/ssh`.

Consequence: Ubuntu/Debian ship `Include /etc/ssh/sshd_config.d/*.conf` at
the TOP of `sshd_config`, so our drop-in must sort FIRST (`00-temper.conf`).
Design stands. (P3 will `sshd -t` before every reload.)

## 2. ssh.socket behavior — CONFIRMED (Ubuntu), PARTIAL (Debian)

Sources: Ubuntu Discourse "SSHD now uses socket-based activation (Ubuntu
22.10 and later)", Launchpad bug #2020560.
Ubuntu >= 22.10 (incl. 24.04/26.04): `ssh.socket` is ENABLED by default and
listens on port 22; each connection spawns `ssh@.service`. `ssh.service`
exists in parallel. Reloading `ssh.service` alone does NOT re-read config
for socket-spawned daemons the way admins expect; the safe sequence is
`sshd -t` then `systemctl restart ssh.socket` (or daemon-reload + restart).
Debian 12/13: classic `ssh.service` by default; `ssh.socket` exists but is
disabled (Debian bug #1077765 documents socket-activation friction).
Our scanner already distinguishes the two (`systemctl list-sockets`); the P3
ssh module must branch on it. OPEN: capture `list-sockets` output on Debian
13 in CI scan-matrix (assert-scan extended in P3).

## 3. deb822 apt format — CONFIRMED

Source: Debian trixie `sources.list(5)` (manpages.debian.org, apt 3.0.3):
`.list` = one-line style (deprecated, removal not before 2029); `.sources`
= deb822 stanzas (`Types/URIs/Suites/Components/Signed-By`, `Enabled: no`
to disable). Defaults: Debian 13 `/etc/apt/sources.list.d/debian.sources`,
Ubuntu >= 24.04 `/etc/apt/sources.list.d/ubuntu.sources`.
Consequence: the mirror module (P3) must read BOTH formats and must never
delete either file — only add/replace its own drop-in + `Enabled:` flips via
backup. Our `collect_net` already detects both. Design stands.

## 4. Default qdisc — CONFIRMED with nuance (corrected)

Sources: `tc(8)` (man7.org): "pfifo_fast qdisc is the automatic default in
the absence of a configured qdisc." Launchpad bug #2003027: Ubuntu images
expect `net.core.default_qdisc=fq_codel` on VMs.
Correction: do NOT claim "Ubuntu sets fq_codel" as a distro fact — on some
images the value comes from systemd's sysctl defaults
(`systemd-sysctl` ships `50-default.conf`-style defaults that distributions
can override), and Debian 13 behavior is UNVERIFIED until the scan-matrix
runs there. Rule: the scanner ALWAYS reads the real value
(`tc qdisc show` in `collect_net`); the network module (P3) branches on the
observed value and sets `fq` explicitly when enabling BBR. No assumptions
anywhere.

## 5. chrony vs systemd-timesyncd — CONFIRMED (with NTS rule)

Sources: Ubuntu Server docs "timedatectl and timesyncd": Ubuntu <= 24.04
default is systemd-timesyncd; "replaced by chrony since Ubuntu 25.10"
(so 26.04 default = chrony with NTS; timesyncd is NOT installed there).
Debian 12/13 default = systemd-timesyncd; chrony optional.
Rules for the time module (P3): DETECT the active daemon
(`systemctl is-active chrony` vs `systemd-timesyncd`) and configure only
that one; NEVER replace NTS sources with non-NTS ones (downgrade attack
surface); SKIP time configuration entirely in containers (no clock control);
never install/remove either daemon. Design stands.

## 6. sudo-rs — CONFIRMED (behavior), OPEN (edge flags)

Sources: Ubuntu Discourse "Adopting sudo-rs by default in Ubuntu 25.10"
(25.10 first default, so 26.04 ships sudo-rs; classic sudo stays
installable), sudo-rs repo: unsupported = INTERCEPT, LDAP sudoers.
Consequence: P0-P2 write NO sudoers content, so no impact now. P3 rule: keep
sudoers snippets to the common subset and validate with `visudo -c`.
OPEN: exact `visudo -c` availability under sudo-rs, verified on the 26.04
scan-matrix VM before P3 writes any sudoers file.

## 7. uutils coreutils — CI-GATED (was: partial)

Sources: uutils project (drop-in goal; deviations treated as bugs), Ubuntu
26.04 ships uutils coreutils with GNU still installable; community reports
of edge-flag differences.
Our posture (already in code): POSIX-only flags everywhere (`grep -E` not
`-P`, `sed -E` not `-r`, no `stat -c`, `ls -ld` parsing instead of stat).
Gate: the `uutils-check` CI job (container `ubuntu:26.04`) records the
`ls --version` / `sudo --version` flavors, runs the FULL bats suite plus a
scanner smoke on uutils coreutils, and fails the build on any deviation.
Until that job is green, P3 module work treats 26.04 as unverified for
shell-behavior edge cases (no new non-POSIX constructs without a test).
