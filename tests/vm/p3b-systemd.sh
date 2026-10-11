#!/usr/bin/env bash
# P3b integration with REAL tools on temp files only (GitHub runners).
# - sshd -t -f on a merged temp config (temp host keys) for ADMIN + TUNNEL.
# - Temporary sshd on port 22222, verified with ss, then killed. Port 22 and
#   the runner's sshd are never touched.
# - nft -c on the generated ruleset (check-only, no kernel change).
# - ufw --dry-run when ufw exists (no system change).
# - Guard-not-confirmed revert with real systemd-run lives in
#   tests/vm/guard-systemd.sh (same CI job).
# Run as root: sudo bash tests/vm/p3b-systemd.sh
# shellcheck shell=bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" != "0" ]]; then
  printf 'error: run as root (sudo bash %s)\n' "$0" >&2
  exit 2
fi
for bin in sshd ssh-keygen ss; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'error: missing %s (install openssh-server, iproute2)\n' "$bin" >&2
    exit 2
  fi
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SRV_TUNE_ROOT="$ROOT"
export SRV_TUNE_TEST=1
export SRV_TUNE_SYSROOT
SRV_TUNE_SYSROOT="$(mktemp -d /tmp/srv-p3b-XXXXXX)"
export SRV_TUNE_STATE_DIR="$SRV_TUNE_SYSROOT/state"
export SRV_TUNE_NO_GUARD=1
mkdir -p "$SRV_TUNE_STATE_DIR/backups"

cleanup() {
  pkill -f "sshd.*srv-p3b" 2>/dev/null || true
  rm -rf "${SRV_TUNE_SYSROOT:-/nonexistent-srv-tune-sysroot}" 2>/dev/null || true
}
trap cleanup EXIT

# shellcheck disable=SC1091
source "$ROOT/lib/modules.sh"

printf '=== 1. sshd -t -f on merged temp configs (ADMIN + TUNNEL) ===\n'
mkdir -p "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d"
ssh-keygen -A -f "$SRV_TUNE_SYSROOT" >/dev/null 2>&1
for mode in ADMIN TUNNEL; do
  export SRV_TUNE_SSH_MODE="$mode"
  export SRV_TUNE_SSH_USER=root
  export SRV_TUNE_TEST_USER_HOME=/root
  module_load ssh
  d="$SRV_TUNE_STATE_DIR/backups/$mode"
  mkdir -p "$d"
  # Real root has host keys; relax the key gate for render testing only by
  # pointing at a home with a valid key when root lacks one.
  if ! ssh_key_ok 2>/dev/null && [[ "$mode" == "ADMIN" ]]; then
    mkdir -p /tmp/srv-p3b-fakeroot/.ssh
    printf 'ssh-ed25519 AAAAintegrationtest root@test\n' >/tmp/srv-p3b-fakeroot/.ssh/authorized_keys
    chmod 700 /tmp/srv-p3b-fakeroot/.ssh
    chmod 600 /tmp/srv-p3b-fakeroot/.ssh/authorized_keys
    export SRV_TUNE_TEST_USER_HOME=/tmp/srv-p3b-fakeroot
  fi
  ssh_apply "$d" >/dev/null || {
    printf 'FAIL: ssh_apply %s failed\n' "$mode" >&2
    exit 1
  }
  merged="$SRV_TUNE_SYSROOT/sshd_config.$mode"
  {
    printf 'Port 22222\nPidFile %s/sshd.pid\n' "$SRV_TUNE_SYSROOT"
    printf 'HostKey %s/etc/ssh/ssh_host_rsa_key\n' "$SRV_TUNE_SYSROOT"
    printf 'HostKey %s/etc/ssh/ssh_host_ed25519_key\n' "$SRV_TUNE_SYSROOT"
    printf 'AuthorizedKeysFile .ssh/authorized_keys\n'
    printf 'Include %s/etc/ssh/sshd_config.d/00-srv-tune.conf\n' "$SRV_TUNE_SYSROOT"
  } >"$merged"
  sshd -t -f "$merged" || {
    printf 'FAIL: sshd -t -f rejected the %s drop-in\n' "$mode" >&2
    exit 1
  }
  printf 'PASS: sshd -t -f accepts %s drop-in\n' "$mode"
done
rm -rf /tmp/srv-p3b-fakeroot

printf '=== 2. temporary sshd on 22222, ss-verified, then killed ===\n'
sshd -f "$SRV_TUNE_SYSROOT/sshd_config.TUNNEL" -E "$SRV_TUNE_SYSROOT/sshd.log"
tries=0
while [[ "$tries" -lt 10 ]]; do
  if ss -tlnp 2>/dev/null | grep -q ':22222 '; then
    break
  fi
  sleep 1
  tries=$((tries + 1))
done
ss -tlnp 2>/dev/null | grep -q ':22222 ' || {
  printf 'FAIL: temp sshd is not listening on 22222\n' >&2
  exit 1
}
printf 'PASS: temp sshd listens on 22222 (runner port 22 untouched)\n'

printf '=== 3. nft -c on the generated ruleset (check-only) ===\n'
if command -v nft >/dev/null 2>&1; then
  module_load firewall
  export SRV_TUNE_SSH_PORT=22222
  d="$SRV_TUNE_STATE_DIR/backups/nft"
  mkdir -p "$d"
  firewall_apply "$d" >/dev/null
  nft -c -f "$SRV_TUNE_SYSROOT/etc/nftables.d/00-srv-tune.nft" || {
    printf 'FAIL: nft -c rejected the generated ruleset\n' >&2
    exit 1
  }
  printf 'PASS: nft -c accepts the generated ruleset\n'
else
  printf 'SKIP: nft missing\n'
fi

printf '=== 4. ufw --dry-run when present ===\n'
if command -v ufw >/dev/null 2>&1; then
  if ufw --dry-run allow 22222/tcp 2>/dev/null | grep -q '22222'; then
    printf 'PASS: ufw --dry-run renders the allow rule\n'
  else
    printf 'SKIP: ufw --dry-run unsupported here\n'
  fi
else
  printf 'SKIP: ufw missing\n'
fi

printf '=== 5. fail2ban jail render ===\n'
module_load fail2ban
export SSH_CONNECTION="198.51.100.9 40000 22"
d="$SRV_TUNE_STATE_DIR/backups/f2b"
mkdir -p "$d"
fail2ban_apply "$d" >/dev/null
grep -q '198.51.100.9' "$SRV_TUNE_SYSROOT/etc/fail2ban/jail.d/00-srv-tune.local"
grep -q 'backend = systemd' "$SRV_TUNE_SYSROOT/etc/fail2ban/jail.d/00-srv-tune.local"
printf 'PASS: fail2ban jail carries the session source\n'

printf '=== 6. kill -9 between write and validate reverts via real timer ===\n'
t6dir="$SRV_TUNE_STATE_DIR/backups/crashx"
mkdir -p "$t6dir"
t6="$SRV_TUNE_STATE_DIR/crash-canary.conf"
printf 'original\n' >"$t6"
cp "$t6" "$t6dir/canary.conf"
printf 'ts\t%s\t%s\n' "$t6" "$t6dir/canary.conf" >"$t6dir/manifest.tsv"
# The "applier" arms a REAL 8s guard, writes (breaks the file), then dies
# exactly where the ssh crash hook fires: after the write, before validate.
SRV_TUNE_STATE_DIR="$SRV_TUNE_STATE_DIR" bash -c "
  source '$ROOT/lib/ssh-guard.sh'
  guard_start crashx 8 >/dev/null
  printf 'broken\n' >'$t6'
  kill -9 \$\$
" &
applier=$!
wait "$applier" 2>/dev/null || true
[[ "$(cat "$t6")" == "broken" ]] || {
  printf 'FAIL: setup did not break the canary\n' >&2
  exit 1
}
sleep 15
[[ "$(cat "$t6")" == "original" ]] || {
  printf 'FAIL: real timer did not revert after kill -9 (got %s)\n' "$(cat "$t6")" >&2
  exit 1
}
printf 'PASS: kill -9 at the crash point still reverted via real timer\n'

printf 'ALL P3B-SYSTEMD CHECKS PASSED\n'
