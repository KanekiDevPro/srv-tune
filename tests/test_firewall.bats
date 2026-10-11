#!/usr/bin/env bats
# firewall + fail2ban: sandboxed, session-cutting rules refused, ignoreip.
# shellcheck shell=bash

load bats_helper

_setup_fw() {
  # $1 = tool stub (ufw|nft|none)
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_NO_GUARD=1
  export SSH_CONNECTION="203.0.113.7 54321 22"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  cat >"$SRV_TUNE_TMP/stubbin/ufw" <<EOF
#!/usr/bin/env bash
if [[ "$1" == "none" ]]; then exit 127; fi
# Active firewall WITHOUT the ssh rule yet: forces the allow-first path.
if [[ "\$1" == "status" ]]; then printf 'Status: active\n'; exit 0; fi
printf 'stub-ufw: %s\n' "\$*" >>"$SRV_TUNE_TMP/ufw.log"
exit 0
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/ufw"
  cat >"$SRV_TUNE_TMP/stubbin/nft" <<'EOF'
#!/usr/bin/env bash
exit ${SRV_TUNE_STUB_NFT_RC:-0}
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/nft"
  if [[ "$1" == "none" ]]; then
    mkdir -p "$SRV_TUNE_TMP/noufw"
    export PATH="$SRV_TUNE_TMP/noufw:/usr/bin:/bin"
  else
    export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  fi
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load firewall
  module_load fail2ban
}

@test "firewall ufw allows the ssh port before enabling" {
  _setup_fw ufw
  d="$SRV_TUNE_STATE_DIR/backups/f1"
  mkdir -p "$d"
  run firewall_apply "$d"
  [ "$status" -eq 0 ]
  # Intent log proves ordering: allow recorded before enable, never reversed.
  allow_line="$(grep -n "^allow 22" "$SRV_TUNE_STATE_DIR/fw-intent.log" | head -n 1 | cut -d: -f1)"
  enable_line="$(grep -n "^enable" "$SRV_TUNE_STATE_DIR/fw-intent.log" | head -n 1 | cut -d: -f1)"
  [ -n "$allow_line" ]
  [ -n "$enable_line" ]
  [ "$allow_line" -lt "$enable_line" ]
  run firewall_verify
  [ "$status" -eq 0 ]
}

@test "firewall nft renders an atomic ruleset with the ssh port" {
  _setup_fw nft
  rm -f "$SRV_TUNE_TMP/stubbin/ufw"
  d="$SRV_TUNE_STATE_DIR/backups/f2"
  mkdir -p "$d"
  run firewall_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/nftables.d/00-srv-tune.nft"
  [ -f "$f" ]
  grep -q "tcp dport" "$f"
  grep -q "22" "$f"
  run firewall_verify
  [ "$status" -eq 0 ]
}

@test "firewall refuses malformed ports instead of writing rules" {
  _setup_fw nft
  rm -f "$SRV_TUNE_TMP/stubbin/ufw"
  printf 'abc\n' >"$SRV_TUNE_STATE_DIR/fw-pending-ports.log"
  tmp="$(mktemp)"
  run firewall_render_nft "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad port"* ]]
}

@test "firewall dry-run writes nothing" {
  _setup_fw ufw
  d="$SRV_TUNE_STATE_DIR/backups/f9"
  mkdir -p "$d"
  export SRV_TUNE_DRY_RUN=1
  run firewall_apply "$d"
  unset SRV_TUNE_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -f "$SRV_TUNE_TMP/ufw.log" ]
}

@test "fail2ban jail carries the session source in ignoreip" {
  _setup_fw none
  d="$SRV_TUNE_STATE_DIR/backups/j1"
  mkdir -p "$d"
  run fail2ban_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/fail2ban/jail.d/00-srv-tune.local"
  grep -q "backend = systemd" "$f"
  grep -q "203.0.113.7" "$f"
  run fail2ban_verify
  [ "$status" -eq 0 ]
}
