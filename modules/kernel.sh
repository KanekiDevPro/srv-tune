#!/usr/bin/env bash
# kernel/resources: swappiness, zram (low RAM + tooling only), journald cap,
# I/O scheduler udev rule, time daemon detected never replaced (NTS kept).
# Contract: kernel_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

kernel_mem_kb() {
  awk '/^MemTotal:/{print $2}' "$(proc_p /proc/meminfo)" 2>/dev/null || printf '0'
}

kernel_swappiness() {
  printf '10\n'
}

# kernel_journal_cap - 10% of free disk on the state fs, clamped 100M..4G.
kernel_journal_cap() {
  local free_kb cap_kb
  free_kb="$(df -k "${SRV_TUNE_SYSROOT:-/}" 2>/dev/null | awk 'NR==2{print $4}' || true)"
  [[ "$free_kb" =~ ^[0-9]+$ ]] || free_kb=1048576
  cap_kb=$((free_kb / 10))
  if [[ "$cap_kb" -lt 102400 ]]; then cap_kb=102400; fi
  if [[ "$cap_kb" -gt 4194304 ]]; then cap_kb=4194304; fi
  if [[ "$cap_kb" -ge 1048576 ]]; then
    printf '%sG\n' "$((cap_kb / 1048576))"
  else
    printf '%sM\n' "$((cap_kb / 1024))"
  fi
}

kernel_is_container() {
  local v
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    v="$(systemd-detect-virt 2>/dev/null || printf 'bare')"
  elif [[ -f /.dockerenv ]]; then
    v="docker"
  else
    v="unknown"
  fi
  case "$v" in
  docker | lxc | openvz | podman | systemd-nspawn) return 0 ;;
  *) return 1 ;;
  esac
}

# kernel_time_daemon - chrony|timesyncd|none. Containers always none.
kernel_time_daemon() {
  if kernel_is_container; then
    printf 'none\n'
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active chrony >/dev/null 2>&1; then
      printf 'chrony\n'
      return 0
    fi
    if systemctl is-active systemd-timesyncd >/dev/null 2>&1; then
      printf 'timesyncd\n'
      return 0
    fi
  fi
  printf 'none\n'
}

kernel_zram_ok() {
  local mem
  mem="$(kernel_mem_kb)"
  [[ "$mem" =~ ^[0-9]+$ ]] || return 1
  if [[ "$mem" -gt 1048576 ]]; then
    return 1
  fi
  command -v zramctl >/dev/null 2>&1 && return 0
  [[ -e /sys/block/zram0 ]] && return 0
  [[ -f "$(sys_p /etc/systemd/zram-generator.conf)" ]] && return 0
  return 1
}

kernel_detect() {
  printf 'MEM_KB=%s\nSWAPPINESS_NOW=%s\nTIME_DAEMON=%s\n' \
    "$(kernel_mem_kb)" \
    "$(cat "$(proc_p /proc/sys/vm/swappiness)" 2>/dev/null || printf unknown)" \
    "$(kernel_time_daemon)"
}

kernel_recommend() {
  printf 'vm.swappiness=10 (why: server default, less swap thrash)\n'
  printf 'journald SystemMaxUse=%s (why: 10%% free disk, clamped 100M-4G)\n' "$(kernel_journal_cap)"
  local mem
  mem="$(kernel_mem_kb)"
  if [[ "$mem" =~ ^[0-9]+$ ]] && [[ "$mem" -le 1048576 ]]; then
    if kernel_zram_ok; then
      printf 'zram enabled (why: <=1GB RAM with zram tooling present)\n'
    else
      printf 'skip zram (why: <=1GB RAM but no zram tooling; not installing)\n'
    fi
  else
    printf 'skip zram (why: RAM above 1GB)\n'
  fi
  printf 'time daemon: %s (why: detected active; NTS sources never replaced; containers skipped)\n' "$(kernel_time_daemon)"
  printf 'I/O scheduler udev rule by disk type (why: none for NVMe, mq-deadline for SSD where offered)\n'
}

# kernel_scheduler_rules <tmpfile> - appends one udev line per suitable disk.
# Prints the rule count.
kernel_scheduler_rules() {
  local out="$1" count=0 d name sched target rot
  for d in /sys/block/*; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    case "$name" in
    loop* | ram* | zram* | dm-* | md*) continue ;;
    esac
    [[ -f "$d/queue/scheduler" ]] || continue
    sched="$(cat "$d/queue/scheduler" 2>/dev/null || printf '')"
    [[ -z "$sched" ]] && continue
    rot="$(cat "$d/queue/rotational" 2>/dev/null || printf '1')"
    target=""
    case "$name" in
    nvme*)
      case "$sched" in
      *'none'*) target="none" ;;
      esac
      ;;
    *)
      if [[ "$rot" == "0" ]]; then
        case "$sched" in
        *'mq-deadline'*) target="mq-deadline" ;;
        *'none'*) target="none" ;;
        esac
      fi
      ;;
    esac
    if [[ -n "$target" ]]; then
      printf 'ACTION=="add|change", KERNEL=="%s", ATTR{queue/scheduler}="%s"\n' "$name" "$target" >>"$out"
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

kernel_apply() {
  local backup_dir="$1" tmp
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  tmp="$(mktemp)"
  {
    printf '# srv-tune kernel (why: computed, see recommend)\nvm.swappiness=%s\n' "$(kernel_swappiness)"
  } >"$tmp"
  apply_file "$backup_dir" "$(sys_p /etc/sysctl.d/00-srv-tune.conf)" "$tmp" "server swappiness" || return 1
  tmp="$(mktemp)"
  {
    printf '# srv-tune journald cap\n[Journal]\nSystemMaxUse=%s\n' "$(kernel_journal_cap)"
  } >"$tmp"
  apply_file "$backup_dir" "$(sys_p /etc/systemd/journald.conf.d/00-srv-tune.conf)" "$tmp" "journald cap" || return 1
  tmp="$(mktemp)"
  if [[ "$(kernel_scheduler_rules "$tmp")" -gt 0 ]]; then
    apply_file "$backup_dir" "$(sys_p /etc/udev/rules.d/60-srv-tune-scheduler.rules)" "$tmp" "scheduler by disk type" || return 1
  else
    printf 'note: no suitable disks for a scheduler rule\n'
    rm -f "$tmp"
  fi
  if kernel_zram_ok; then
    tmp="$(mktemp)"
    {
      printf '# srv-tune zram (low RAM, tooling present)\n[zram0]\nzram-size = min(ram, 4096)\n'
    } >"$tmp"
    apply_file "$backup_dir" "$(sys_p /etc/systemd/zram-generator.conf)" "$tmp" "zram on low RAM" || return 1
  else
    printf 'note: zram skipped (see recommend)\n'
  fi
  local daemon
  daemon="$(kernel_time_daemon)"
  if [[ "$daemon" == "chrony" ]]; then
    # makestep only: initial-sync fix, never touches sources (NTS preserved).
    tmp="$(mktemp)"
    printf '# srv-tune chrony: initial step only; sources/NTS untouched\nmakestep 1 -1\n' >"$tmp"
    apply_file "$backup_dir" "$(sys_p /etc/chrony/conf.d/00-srv-tune-makestep.conf)" "$tmp" "chrony makestep" || return 1
  else
    printf 'note: time daemon is %s, nothing to configure (timesyncd uses vendor defaults; containers skipped)\n' "$daemon"
  fi
  return 0
}

kernel_verify() {
  local f
  f="$(sys_p /etc/sysctl.d/00-srv-tune.conf)"
  if [[ ! -f "$f" ]]; then
    printf 'error: kernel sysctl drop-in missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q "vm.swappiness=$(kernel_swappiness)" "$f" || {
    printf 'error: swappiness line missing in %s\n' "$f" >&2
    return 1
  }
  f="$(sys_p /etc/systemd/journald.conf.d/00-srv-tune.conf)"
  if [[ ! -f "$f" ]]; then
    printf 'error: journald drop-in missing: %s\n' "$f" >&2
    return 1
  fi
  grep -q "SystemMaxUse=" "$f" || {
    printf 'error: SystemMaxUse missing in %s\n' "$f" >&2
    return 1
  }
  # NTS guard: our chrony drop-in must never carry sources.
  f="$(sys_p /etc/chrony/conf.d/00-srv-tune-makestep.conf)"
  if [[ -f "$f" ]]; then
    if grep -Eq '^[[:space:]]*(server|pool|source|nts)' "$f"; then
      printf 'error: chrony drop-in touches sources (NTS rule violated)\n' >&2
      return 1
    fi
    if [[ "$(kernel_time_daemon)" != "chrony" ]]; then
      printf 'error: chrony drop-in written but chrony is not the active daemon\n' >&2
      return 1
    fi
  fi
  return 0
}
