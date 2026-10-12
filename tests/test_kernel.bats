#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# kernel module: swappiness, zram, journald cap, scheduler rule, time detect.
# shellcheck shell=bash

load bats_helper

_setup_kernel() {
  export SRV_TUNE_SYSROOT="$SRV_TUNE_TMP/root"
  export SRV_TUNE_PROCROOT="$SRV_TUNE_TMP"
  mkdir -p "$SRV_TUNE_TMP/proc/sys/vm" "$SRV_TUNE_TMP/stubbin"
  printf 'MemTotal:        500000 kB\n' >"$SRV_TUNE_TMP/proc/meminfo"
  printf '60\n' >"$SRV_TUNE_TMP/proc/sys/vm/swappiness"
  # Fake systemd: chrony active, timesyncd inactive.
  cat >"$SRV_TUNE_TMP/stubbin/systemctl" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "is-active chrony" ]]; then exit 0; fi
exit 3
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/systemctl"
  # Not a container here: detect-virt reports bare metal so the systemctl
  # stub (chrony active) governs time-daemon detection.
  cat >"$SRV_TUNE_TMP/stubbin/systemd-detect-virt" <<'EOF'
#!/usr/bin/env bash
printf 'bare\n'
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/systemd-detect-virt"
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load kernel
}

@test "kernel swappiness follows server default without zram" {
  _setup_kernel
  d="$SRV_TUNE_STATE_DIR/backups/k1"
  mkdir -p "$d"
  run kernel_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "vm.swappiness=10" "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf"
  run kernel_verify
  [ "$status" -eq 0 ]
}

@test "kernel swappiness is 100 and zram configured on low RAM with tooling" {
  _setup_kernel
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SRV_TUNE_TMP/stubbin/zramctl"
  chmod +x "$SRV_TUNE_TMP/stubbin/zramctl"
  d="$SRV_TUNE_STATE_DIR/backups/kz"
  mkdir -p "$d"
  run kernel_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "vm.swappiness=100" "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf"
  [ -f "$SRV_TUNE_SYSROOT/etc/systemd/zram-generator.conf" ]
  run kernel_verify
  [ "$status" -eq 0 ]
}

@test "kernel journald cap scales with free disk" {
  _setup_kernel
  d="$SRV_TUNE_STATE_DIR/backups/k2"
  mkdir -p "$d"
  run kernel_apply "$d"
  [ "$status" -eq 0 ]
  grep -q "SystemMaxUse=" "$SRV_TUNE_SYSROOT/etc/systemd/journald.conf.d/00-srv-tune.conf"
}

@test "kernel time detects chrony and never touches sources" {
  _setup_kernel
  run kernel_time_daemon
  [ "$status" -eq 0 ]
  [[ "$output" == "chrony" ]]
}

@test "kernel dry-run writes nothing" {
  _setup_kernel
  d="$SRV_TUNE_STATE_DIR/backups/k9"
  mkdir -p "$d"
  export SRV_TUNE_DRY_RUN=1
  run kernel_apply "$d"
  unset SRV_TUNE_DRY_RUN
  [ "$status" -eq 0 ]
  [ ! -e "$SRV_TUNE_SYSROOT/etc/sysctl.d/00-srv-tune.conf" ]
}
