#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tunnel integration with REAL tools on temp files only (CI runners).
# - real ssh-keygen: add/list/remove through the CLI as root
# - real sshd -t / sshd -T on the rendered TUNNEL drop-in
# Port 22, /etc/ssh, and the runner's sshd are never touched.
# Run as root: sudo bash tests/vm/tunnel-systemd.sh
# shellcheck shell=bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" != "0" ]]; then
  printf 'error: run as root (sudo bash %s)\n' "$0" >&2
  exit 2
fi
for bin in ssh-keygen sshd; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf 'error: missing %s (install openssh-server)\n' "$bin" >&2
    exit 2
  fi
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SRV_TUNE_ROOT="$ROOT"
export SRV_TUNE_STATE_DIR="$TMP/state"
export SRV_TUNE_LOCK_FILE="$TMP/lock"
export SRV_TUNE_TUNNEL_HOME="$TMP/home/tunnel"
export SRV_TUNE_TUNNEL_USER=nobody
export SRV_TUNE_TEST=0
mkdir -p "$SRV_TUNE_TUNNEL_HOME/.ssh"

fail() {
  printf 'TUNNEL-INTEGRATION-FAIL: %s\n' "$1" >&2
  exit 1
}

ssh-keygen -q -t ed25519 -N '' -f "$TMP/id"
bash "$ROOT/optimizer.sh" tunnel keys add --file "$TMP/id.pub" --comment ci >/dev/null

keys="$SRV_TUNE_TUNNEL_HOME/.ssh/authorized_keys"
[[ -s "$keys" ]] || fail "authorized_keys missing"
[[ "$(stat -c '%a' "$keys")" == "600" ]] || fail "authorized_keys mode is not 600"
fp="$(ssh-keygen -lf "$keys" | awk '{print $2}')"
bash "$ROOT/optimizer.sh" tunnel keys list --json | grep -q "\"fp\":\"$fp\"" ||
  fail "keys list does not show $fp"
ls "$SRV_TUNE_STATE_DIR"/backups/keys-* >/dev/null || fail "no key backup"
grep -q 'action=key-add' "$SRV_TUNE_STATE_DIR/tunnel-actions.log" ||
  fail "no key-add audit line"

bash "$ROOT/optimizer.sh" tunnel keys remove --fp "$fp" >/dev/null
[[ ! -s "$keys" ]] || fail "authorized_keys not empty after remove"
grep -q 'action=key-remove' "$SRV_TUNE_STATE_DIR/tunnel-actions.log" ||
  fail "no key-remove audit line"

# Render the TUNNEL drop-in and validate it with the real sshd.
export SRV_TUNE_SYSROOT="$TMP/root"
mkdir -p "$SRV_TUNE_SYSROOT/etc/ssh/sshd_config.d"
export SRV_TUNE_SSH_PORT=2222
export SRV_TUNE_PERMIT_OPEN="db.internal:5432"
export SRV_TUNE_TUNNEL_GATEWAY=1
export SRV_TUNE_TUNNEL_MODE=tun
export SRV_TUNE_PROFILE=vpn-tunnel
export SRV_TUNE_TUNNEL_USER=root
# shellcheck disable=SC1091
source "$ROOT/lib/modules.sh"
# shellcheck disable=SC1091
source "$ROOT/modules/ssh.sh"
conf="$TMP/00-srv-tune.conf"
ssh_render_tunnel "$conf"
sshd -t -f "$conf" || fail "sshd rejects the rendered TUNNEL drop-in"
sshd -T -C user=root,host=localhost,addr=127.0.0.1 -f "$conf" |
  grep -qi 'permitopen db.internal:5432' || fail "PermitOpen missing from effective config"
grep -q '^GatewayPorts yes' "$conf" || fail "GatewayPorts missing"
grep -q '^PermitTunnel yes' "$conf" || fail "PermitTunnel missing"

printf 'tunnel integration: ok\n'
