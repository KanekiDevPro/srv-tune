#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# network module: computed sysctl drop-in, container behavior, denylist.
# shellcheck shell=bash

load bats_helper

_setup_net() {
  # $1 = virt to report via stub systemd-detect-virt
  export TEMPER_SYSROOT="$TEMPER_TMP/root"
  export TEMPER_PROCROOT="$TEMPER_TMP"
  export TEMPER_NIC_SPEED_MBPS=1000
  mkdir -p "$TEMPER_TMP/proc/sys/net/ipv4" "$TEMPER_TMP/stubbin"
  printf 'MemTotal:        8192000 kB\n' >"$TEMPER_TMP/proc/meminfo"
  printf 'cubic reno bbr\n' >"$TEMPER_TMP/proc/sys/net/ipv4/tcp_available_congestion_control"
  printf 'cubic\n' >"$TEMPER_TMP/proc/sys/net/ipv4/tcp_congestion_control"
  for k in tcp_rmem tcp_wmem tcp_max_syn_backlog tcp_fastopen; do
    printf 'x\n' >"$TEMPER_TMP/proc/sys/net/ipv4/$k"
  done
  mkdir -p "$TEMPER_TMP/proc/sys/net/core"
  for k in rmem_max wmem_max somaxconn default_qdisc; do
    printf 'x\n' >"$TEMPER_TMP/proc/sys/net/core/$k"
  done
  mkdir -p "$TEMPER_TMP/proc/sys/net/netfilter"
  printf 'x\n' >"$TEMPER_TMP/proc/sys/net/netfilter/nf_conntrack_max"
  cat >"$TEMPER_TMP/stubbin/systemd-detect-virt" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1"
EOF
  chmod +x "$TEMPER_TMP/stubbin/systemd-detect-virt"
  # A sysctl stub that FAILS if ever called: proves sandboxed tests stay clean.
  cat >"$TEMPER_TMP/stubbin/sysctl" <<EOF
#!/usr/bin/env bash
printf 'CALLED\n' >>"$TEMPER_TMP/sysctl.log"
exit 1
EOF
  chmod +x "$TEMPER_TMP/stubbin/sysctl"
  rm -f "$TEMPER_TMP/sysctl.log"
  export PATH="$TEMPER_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/lib/modules.sh"
  module_load network
}

@test "network conf enables bbr and fq when available" {
  _setup_net none
  d="$TEMPER_STATE_DIR/backups/n1"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  f="$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf"
  [ -f "$f" ]
  grep -q "net.ipv4.tcp_congestion_control=bbr" "$f"
  grep -q "net.core.default_qdisc=fq" "$f"
  run network_verify
  [ "$status" -eq 0 ]
}

@test "network conf never contains banned knobs" {
  _setup_net none
  d="$TEMPER_STATE_DIR/backups/n2"
  mkdir -p "$d"
  network_apply "$d"
  f="$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf"
  for knob in tcp_tw_recycle ip_forward rp_filter accept_source_route; do
    [ "$(grep -c "$knob" "$f")" -eq 0 ]
  done
}

@test "network skips live writes in containers but keeps the drop-in" {
  _setup_net docker
  d="$TEMPER_STATE_DIR/backups/n3"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  [ -f "$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf" ]
  [ ! -f "$TEMPER_TMP/sysctl.log" ]
}

@test "network skips keys missing from this kernel" {
  _setup_net none
  rm -f "$TEMPER_TMP/proc/sys/net/ipv4/tcp_fastopen"
  d="$TEMPER_STATE_DIR/backups/n4"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  run grep -q "tcp_fastopen" "$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf"
  [ "$status" -ne 0 ]
}

@test "network distrusts absurd VM link speeds (RAM share governs)" {
  _setup_net none
  export TEMPER_NIC_SPEED_MBPS=100000
  d="$TEMPER_STATE_DIR/backups/n5"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "net.core.rmem_max=268435456" "$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf"
  unset TEMPER_NIC_SPEED_MBPS
}

@test "network caps buffers by link BDP on slow links" {
  _setup_net none
  export TEMPER_NIC_SPEED_MBPS=10
  d="$TEMPER_STATE_DIR/backups/n6"
  mkdir -p "$d"
  run network_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "net.core.rmem_max=4194304" "$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf"
  unset TEMPER_NIC_SPEED_MBPS
}

@test "network dry-run writes nothing" {
  _setup_net none
  d="$TEMPER_STATE_DIR/backups/n9"
  mkdir -p "$d"
  export TEMPER_DRY_RUN=1
  run network_apply "$d"
  unset TEMPER_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -e "$TEMPER_SYSROOT/etc/sysctl.d/00-temper.conf" ]
}
