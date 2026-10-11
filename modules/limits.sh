#!/usr/bin/env bash
# limits: nofile/nproc from RAM and CPU (hard <= fs.nr_open), systemd
# DefaultLimitNOFILE drop-ins, core dumps off by default (debug opt-in).
# Contract: limits_detect|recommend|apply|verify. 0 ok, 2 skip, 1 failure.
# shellcheck shell=bash

limits_mem_kb() {
  local r="${SRV_TUNE_PROCROOT:-}"
  awk '/^MemTotal:/{print $2}' "${r}/proc/meminfo" 2>/dev/null || printf '0'
}

limits_nr_open() {
  local r="${SRV_TUNE_PROCROOT:-}"
  cat "${r}/proc/sys/fs/nr_open" 2>/dev/null || printf '1048576'
}

limits_cpu_cores() {
  if command -v nproc >/dev/null 2>&1; then
    nproc 2>/dev/null || printf '1'
  else
    printf '1'
  fi
}

# limits_values - prints "HARD SOFT NPROC" computed from this machine.
limits_values() {
  local mem nr cores hard soft nproc
  mem="$(limits_mem_kb)"
  nr="$(limits_nr_open)"
  cores="$(limits_cpu_cores)"
  [[ "$mem" =~ ^[0-9]+$ ]] || mem=0
  [[ "$nr" =~ ^[0-9]+$ ]] || nr=1048576
  [[ "$cores" =~ ^[0-9]+$ ]] || cores=1
  # hard: 64k base, +64k per GB RAM, capped by fs.nr_open (why: fd table).
  hard=$((65536 + (mem / 1048576) * 65536))
  if [[ "$hard" -gt "$nr" ]]; then hard="$nr"; fi
  soft=$((hard / 2))
  nproc=$((cores * 4096))
  printf '%s %s %s\n' "$hard" "$soft" "$nproc"
}

limits_detect() {
  local nr hard_now
  nr="$(limits_nr_open)"
  hard_now="$(ulimit -Hn 2>/dev/null || printf 'unknown')"
  printf 'NR_OPEN=%s\nNOFILE_HARD_NOW=%s\n' "$nr" "$hard_now"
}

limits_recommend() {
  local hard soft nproc
  read -r hard soft nproc < <(limits_values)
  printf 'nofile hard %s (why: 64k + 64k/GB RAM, capped by fs.nr_open)\n' "$hard"
  printf 'nofile soft %s (why: half of hard)\n' "$soft"
  printf 'nproc %s (why: 4096 per CPU core)\n' "$nproc"
  printf 'core dumps off (why: disk/incident hygiene; SRV_TUNE_DEBUG=1 opts out)\n'
}

limits_apply() {
  local backup_dir="$1" hard soft nproc f
  read -r hard soft nproc < <(limits_values)
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/dryrun.sh"
  f="$(mktemp)"
  {
    printf '# srv-tune limits (why: computed, see recommend)\n'
    printf '* soft nofile %s\n' "$soft"
    printf '* hard nofile %s\n' "$hard"
    printf '* soft nproc %s\n' "$nproc"
    printf '* hard nproc %s\n' "$nproc"
    if [[ "${SRV_TUNE_DEBUG:-0}" != "1" ]]; then
      printf '* hard core 0\n'
    fi
  } >"$f"
  apply_file "$backup_dir" "$(sys_p /etc/security/limits.d/00-srv-tune.conf)" "$f" "nofile/nproc from RAM/CPU" || return 1
  f="$(mktemp)"
  {
    printf '# srv-tune systemd limits\n[Manager]\nDefaultLimitNOFILE=%s:%s\n' "$soft" "$hard"
  } >"$f"
  apply_file "$backup_dir" "$(sys_p /etc/systemd/system.conf.d/00-srv-tune.conf)" "$f" "systemd DefaultLimitNOFILE" || return 1
  f="$(mktemp)"
  {
    printf '# srv-tune systemd user limits\n[Manager]\nDefaultLimitNOFILE=%s:%s\n' "$soft" "$hard"
  } >"$f"
  apply_file "$backup_dir" "$(sys_p /etc/systemd/user.conf.d/00-srv-tune.conf)" "$f" "systemd user DefaultLimitNOFILE" || return 1
  if [[ "${SRV_TUNE_DEBUG:-0}" != "1" ]]; then
    f="$(mktemp)"
    {
      printf '# srv-tune coredump off\n[Coredump]\nStorage=none\n'
    } >"$f"
    apply_file "$backup_dir" "$(sys_p /etc/systemd/coredump.conf.d/00-srv-tune.conf)" "$f" "core dumps off" || return 1
  fi
  return 0
}

limits_verify() {
  local hard soft nproc
  read -r hard soft nproc < <(limits_values)
  local f
  f="$(sys_p /etc/security/limits.d/00-srv-tune.conf)"
  [[ -f "$f" ]] || {
    printf 'error: limits drop-in missing: %s\n' "$f" >&2
    return 1
  }
  grep -q "hard nofile $hard" "$f" || {
    printf 'error: limits drop-in lacks hard nofile %s\n' "$hard" >&2
    return 1
  }
  local nr
  nr="$(limits_nr_open)"
  if [[ "$hard" -gt "$nr" ]]; then
    printf 'error: hard %s exceeds fs.nr_open %s\n' "$hard" "$nr" >&2
    return 1
  fi
  return 0
}
