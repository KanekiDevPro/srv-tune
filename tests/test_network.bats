#!/usr/bin/env bats
# network module: computed sysctl drop-in, container behavior, denylist.
# shellcheck shell=bash

load bats_helper

_setup_net() {
  # $1 = virt to report via stub systemd-detect-virt
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  export SRV_TUNE_NIC_SPEED_MBPS=1000
  mkdir -p "$SRV_TUNE_TMP/proc/sys/net/ipv4" "$SRV_TUNE_TMP/stubbin"
  printf 'MemTotal:        8192000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf 'cubic reno bbr\n' >"$SRV_TUNE_TMP/proc/sys/net/ipv4/tcp_available_congestion_control"
  printf 'cubic\n' >"$SRV_TUNE_TMP/proc/sys/net/ipv4/tcp_congestion_control"
  for k in tcp_rmem tcp_wmem tcp_max_syn_backlog tcp_fastopen; do
    printf 'x\n' >"$SRV_TUNE_TMP/proc/sys/net/ipv4/$k"
  done
  mkdir -p "$SRV_TUNE_TMP/proc/sys/net/core"
  for k in rmem_max wmem_max somaxconn default_qdisc; do
    printf 'x\n' >"$SRV_TUNE_TMP/proc/sys/net/core/$k"
  done
  mkdir -p "$SRV_TUNE_TMP/proc/sys/net/netfilter"
  printf 'x\n' >"$SRV_TUNE_TMP/proc/sys/net/netfilter/nf_conntrack_max"
  cat >"$SRV_TUNE_TMP/stubbin/systemd-detect-virt" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1"
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/systemd-detect-virt"
  # A sysctl stub that FAILS if ever called: proves sandboxed tests stay clean.
  cat >"$SRV_TUNE_TMP/stubbin/sysctl" <<EOF
#!/usr/bin/env bash
printf 'CALLED\n' >>"$SRV_TUNE_TMP/sysctl.log"
exit 1
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/sysctl"
  rm -f "$SRV_TUNE_TMP/sysctl.log"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load network
}

@test "network conf enables bbr and fq when available" {
  _setup_net none
  d="$SRV_TUNE_STATE_DIR/backups/n1"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  f="$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf"
  [ -f "$f" ]
  grep -q "net.ipv4.tcp_congestion_control=bbr" "$f"
  grep -q "net.core.default_qdisc=fq" "$f"
  run network_verify
  [ "$status" -eq 0 ]
}

@test "network conf never contains banned knobs" {
  _setup_net none
  d="$SRV_TUNE_STATE_DIR/backups/n2"
  mkdir -p "$d"
  network_apply "$d"
  f="$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf"
  for knob in tcp_tw_recycle ip_forward rp_filter accept_source_route; do
    [ "$(grep -c "$knob" "$f")" -eq 0 ]
  done
}

@test "network skips live writes in containers but keeps the drop-in" {
  _setup_net docker
  d="$SRV_TUNE_STATE_DIR/backups/n3"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf" ]
  [ ! -f "$SRV_TUNE_TMP/sysctl.log" ]
}

@test "network skips keys missing from this kernel" {
  _setup_net none
  rm -f "$SRV_TUNE_TMP/proc/sys/net/ipv4/tcp_fastopen"
  d="$SRV_TUNE_STATE_DIR/backups/n4"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  run grep -q "tcp_fastopen" "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf"
  [ "$status" -ne 0 ]
}

@test "network dry-run writes nothing" {
  _setup_net none
  d="$SRV_TUNE_STATE_DIR/backups/n9"
  mkdir -p "$d"
  export SRV_TUNE_DRY_RUN=1
  run network_apply "$d"
  unset SRV_TUNE_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf" ]
}
