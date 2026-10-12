#!/usr/bin/env bats
# firewall + fail2ban: sandboxed, session-cutting rules refused, ignoreip.
# shellcheck shell=bash

load bats_helper

_setup_fw() {
  # $1 = tool stub (ufw|nft|none). The tool is injected via
  # SRV_TUNE_FIREWALL_TOOL (same override pattern as SRV_TUNE_DNS_TOOL), so
  # no real firewall binary is ever consulted and PATH stays intact.
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_NO_GUARD=1
  export SSH_CONNECTION="203.0.113.7 54321 22"
  mkdir -p "$SRV_TUNE_TMP/stubbin" "$SRV_TUNE_SYSROOT/etc"
  case "$1" in
  ufw) export SRV_TUNE_FIREWALL_TOOL=ufw ;;
  nft) export SRV_TUNE_FIREWALL_TOOL=nftables ;;
  none) export SRV_TUNE_FIREWALL_TOOL=none ;;
  esac
  if [[ "$1" == "nft" ]]; then
    cat >"$SRV_TUNE_TMP/stubbin/nft" <<'EOF'
#!/usr/bin/env bash
exit ${SRV_TUNE_STUB_NFT_RC:-0}
EOF
    chmod +x "$SRV_TUNE_TMP/stubbin/nft"
  fi
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
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

@test "firewall ufw ensures IPV6 coverage" {
  _setup_fw ufw
  mkdir -p "$SRV_TUNE_SYSROOT/etc/default"
  printf 'IPV6=no\n' >"$SRV_TUNE_SYSROOT/etc/default/ufw"
  d="$SRV_TUNE_STATE_DIR/backups/fv6"
  mkdir -p "$d"
  run firewall_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "^IPV6=yes" "$SRV_TUNE_SYSROOT/etc/default/ufw"
}

@test "firewall nft renders an atomic ruleset with the ssh port" {
  _setup_fw nft
  d="$SRV_TUNE_STATE_DIR/backups/f2"
  mkdir -p "$d"
  run firewall_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/nftables.d/00-srv-tune.nft"
  [ -f "$f" ]
  grep -q "table inet srv_tune" "$f"
  grep -q "tcp dport" "$f"
  grep -q "22" "$f"
  run firewall_verify
  [ "$status" -eq 0 ]
}

@test "firewall refuses malformed ports instead of writing rules" {
  _setup_fw nft
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

_setup_nft_store() {
  # Stateful nft stub: tables live in $SRV_TUNE_TMP/nft-store, one per line.
  printf 'ip docker\n' >"$SRV_TUNE_TMP/nft-store"
  cat >"$SRV_TUNE_TMP/stubbin/nft" <<'EOF'
#!/usr/bin/env bash
store="${SRV_TUNE_NFT_STORE:?}"
case "$1" in
  -c) grep -q 'table inet srv_tune' "$3" ;;
  -f)
    grep -E '^table [a-z0-9]+ [a-z0-9_]+' "$2" | awk '{print $2, $3}' >>"$store"
    sort -u "$store" -o "$store"
    ;;
  list) cat "$store" ;;
  delete)
    grep -v -x -F "$3 $4" "$store" >"$store.tmp" || true
    mv "$store.tmp" "$store"
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/nft"
  export SRV_TUNE_NFT_STORE="$SRV_TUNE_TMP/nft-store"
}

@test "nft apply touches only our table; foreign tables survive" {
  _setup_fw nft
  _setup_nft_store
  tmp="$(mktemp)"
  firewall_render_nft "$tmp"
  run firewall_ensure_nft "$tmp"
  [ "$status" -eq 0 ]
  grep -q '^table inet srv_tune' "$tmp"
  run nft list ruleset
  [ "$status" -eq 0 ]
  [[ "$output" == *"ip docker"* ]]
  [[ "$output" == *"inet srv_tune"* ]]
}

@test "nft rollback removes only our table" {
  _setup_fw nft
  _setup_nft_store
  tmp="$(mktemp)"
  firewall_render_nft "$tmp"
  firewall_ensure_nft "$tmp"
  run firewall_rollback_live
  [ "$status" -eq 0 ]
  run nft list ruleset
  [[ "$output" == *"ip docker"* ]]
  [[ "$output" != *"srv_tune"* ]]
}
