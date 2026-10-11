#!/usr/bin/env bash
# P3a module framework: profiles, --only filter, SYSROOT sandboxing,
# detect/recommend/apply/verify/rollback orchestration with auto-rollback.
# Module contract: <m>_detect | <m>_recommend | <m>_apply <backup_dir> |
# <m>_verify ; each returns 0 ok, 2 skip (message on stdout), 1 failure.
# shellcheck shell=bash

if [[ -n "${__SRV_TUNE_MODULES_SOURCED:-}" ]]; then
  return 0
fi
__SRV_TUNE_MODULES_SOURCED=1

# sys_p <abs path> - prepend SRV_TUNE_SYSROOT (tests) for sandboxed apply.
sys_p() {
  local p="$1" r="${SRV_TUNE_SYSROOT:-/}"
  if [[ "$r" == "/" || "$p" != /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$r" "$p"
  fi
}

# proc_p <abs /proc path> - prepend SRV_TUNE_PROCROOT (tests) for fake kernels.
proc_p() {
  local p="$1" r="${SRV_TUNE_PROCROOT:-}"
  if [[ -z "$r" ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$r" "$p"
  fi
}

# module_load <name> - source modules/<name>.sh from the install root.
module_load() {
  local m="$1" root="${SRV_TUNE_ROOT:-.}"
  if [[ ! -f "$root/modules/$m.sh" ]]; then
    printf 'error: unknown module: %s\n' "$m" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$root/modules/$m.sh"
}

# profile_modules <profile> - prints the module list, one per line.
profile_modules() {
  local profile="$1" root="${SRV_TUNE_ROOT:-.}" file mods
  file="$root/profiles/$profile.conf"
  if [[ ! -f "$file" ]]; then
    printf 'error: unknown profile: %s\n' "$profile" >&2
    return 1
  fi
  mods="$(grep -E '^modules=' "$file" | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
  local m
  # shellcheck disable=SC2086
  for m in $mods; do
    # Strip workload/ prefix segments down to the file name for --only match.
    printf '%s\n' "${m##*/}"
  done
}

# profile_env <profile> - export profile settings (ssh_mode, ...) as
# SRV_TUNE_* vars for modules. Only simple KEY=value lines; modules= ignored.
profile_env() {
  local profile="$1" root="${SRV_TUNE_ROOT:-.}" file line k v
  file="$root/profiles/$profile.conf"
  [[ -f "$file" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
    '' | \#* | modules=*) continue ;;
    esac
    k="$(printf '%s' "$line" | cut -d= -f1)"
    v="$(printf '%s' "$line" | cut -d= -f2- | tr -d '"')"
    case "$k" in
    '' | *[!A-Za-z_]*) continue ;;
    esac
    k="$(printf '%s' "$k" | tr 'a-z' 'A-Z')"
    export "SRV_TUNE_$k=$v"
  done <"$file"
  export SRV_TUNE_PROFILE="$profile"
  return 0
}

# run_apply <profile> <only_csv> - full APPLY with auto-rollback. Stops at
# the first failing module; earlier modules stay applied (each verified).
run_apply() {
  local profile="$1" only="${2:-}" m id dir rc
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/state.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/backup.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/rollback.sh"
  state_init || return 1
  profile_env "$profile" || return 1
  local ran=0
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    if [[ -n "$only" ]] && [[ ",$only," != *",$m,"* ]]; then
      continue
    fi
    if [[ ! -f "${SRV_TUNE_ROOT:-.}/modules/$m.sh" ]]; then
      if [[ -n "$only" ]]; then
        printf 'error: unknown module: %s\n' "$m" >&2
        return 1
      fi
      printf 'skip: module %s is not implemented yet\n' "$m"
      continue
    fi
    module_load "$m" || return 1
    printf '=== module: %s ===\n' "$m"
    "${m}_recommend" || true
    if [[ "${SRV_TUNE_DRY_RUN:-0}" == "1" ]]; then
      # Dry-run: show diffs only. No backup, no verify, no rollback, no log.
      "${m}_apply" "$SRV_TUNE_STATE_DIR/backups/dry-run" || return 1
      printf 'dry-run: %s (no changes made)\n' "$m"
      ran=$((ran + 1))
      continue
    fi
    id="$(new_backup_id)"
    dir="${SRV_TUNE_STATE_DIR:-/var/lib/srv-tune}/backups/$id"
    mkdir -p "$dir" || return 1
    "${m}_apply" "$dir"
    rc=$?
    if [[ "$rc" == "2" ]]; then
      printf 'skip: %s has nothing to do here (see notes above)\n' "$m"
      rm -rf "$dir"
      continue
    fi
    if [[ "$rc" -ne 0 ]]; then
      printf 'error: %s apply failed; nothing was kept\n' "$m" >&2
      return 1
    fi
    if ! "${m}_verify"; then
      printf 'error: %s health-check failed; rolling back %s\n' "$m" "$id" >&2
      rollback_id "$id" || true
      return 1
    fi
    state_log_applied "module=$m backup=$id"
    printf 'ok: %s applied (backup %s)\n' "$m" "$id"
    ran=$((ran + 1))
  done < <(profile_modules "$profile")
  if [[ -n "$only" && "$ran" == "0" ]]; then
    printf 'error: --only matched no module in profile %s: %s\n' "$profile" "$only" >&2
    return 1
  fi
  rc=0
  return "$rc"
}

# module_explain <name> - one-paragraph why for `optimizer explain`.
module_explain() {
  case "$1" in
  limits)
    printf 'limits: raises nofile/nproc from RAM and CPU count (capped by fs.nr_open), disables core dumps by default; drop-ins only.\n'
    ;;
  network)
    printf 'network: BBR+fq when the kernel offers it, TCP buffers from RAM and NIC speed, somaxconn/backlog, conntrack sizing; never tcp_tw_recycle; containers get drop-ins without live writes.\n'
    ;;
  kernel)
    printf 'kernel: swappiness for servers, zram on <=1GB only with tooling present, journald cap from free disk, I/O scheduler udev rule by disk type, time daemon detected never replaced (NTS preserved), containers skipped.\n'
    ;;
  dns)
    printf 'dns: benchmarks candidate resolvers live (latency plus failure rate) with timeouts, honors systemd-resolved/resolv.conf/netplan, respects cloud-init, rolls back when resolution breaks.\n'
    ;;
  mirror)
    printf 'mirror: handles sources.list AND deb822, benchmarks mirrors live, swaps only the URI, verifies with apt update; pip/npm/docker registry mirrors are opt-in file writes.\n'
    ;;
  ssh)
    printf 'ssh: ADMIN/TUNNEL/CUSTOM modes (P3b, not implemented yet).\n'
    ;;
  security | cleanup | docker | nginx | db)
    printf '%s: planned module, not implemented in P3a.\n' "$1"
    ;;
  *)
    printf 'error: unknown module: %s\n' "$1" >&2
    return 1
    ;;
  esac
}
