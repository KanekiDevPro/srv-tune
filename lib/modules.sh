#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# P3a module framework: profiles, --only filter, SYSROOT sandboxing,
# detect/recommend/apply/verify/rollback orchestration with auto-rollback.
# Module contract: <m>_detect | <m>_recommend | <m>_apply <backup_dir> |
# <m>_verify ; each returns 0 ok, 2 skip (message on stdout), 1 failure.
# shellcheck shell=bash

if [[ -n "${__TEMPER_MODULES_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_MODULES_SOURCED=1

# sys_p <abs path> - prepend TEMPER_SYSROOT (tests) for sandboxed apply.
sys_p() {
  local p="$1" r="${TEMPER_SYSROOT:-/}"
  if [[ "$r" == "/" || "$p" != /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$r" "$p"
  fi
}

# proc_p <abs /proc path> - prepend TEMPER_PROCROOT (tests) for fake kernels.
proc_p() {
  local p="$1" r="${TEMPER_PROCROOT:-}"
  if [[ -z "$r" ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$r" "$p"
  fi
}

# module_load <name> - source modules/<name>.sh from the install root.
module_load() {
  local m="$1" root="${TEMPER_ROOT:-.}"
  if [[ ! -f "$root/modules/$m.sh" ]]; then
    printf 'error: unknown module: %s\n' "$m" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "$root/modules/$m.sh"
}

# profile_file <profile> - resolve the .conf path, validating --config.
profile_file() {
  local profile="$1" root="${TEMPER_ROOT:-.}" custom="${TEMPER_CUSTOM_PROFILE:-}"
  if [[ "$profile" == "custom" && -n "$custom" ]]; then
    if [[ ! -f "$custom" ]]; then
      printf 'error: --config file not found: %s\n' "$custom" >&2
      return 1
    fi
    local mods m k
    mods="$(grep -E '^modules=' "$custom" | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
    if [[ -z "$mods" ]]; then
      printf 'error: --config %s has no modules= line\n' "$custom" >&2
      return 1
    fi
    # shellcheck disable=SC2086
    for m in $mods; do
      m="${m##*/}"
      if [[ ! -f "$root/modules/$m.sh" ]]; then
        case "$m" in
        security | cleanup | docker | nginx | db) ;;
        *)
          printf 'error: --config %s lists unknown module: %s\n' "$custom" "$m" >&2
          return 1
          ;;
        esac
      fi
    done
    while IFS= read -r line; do
      case "$line" in
      '' | \#* | modules=*) continue ;;
      esac
      k="$(printf '%s' "$line" | cut -d= -f1)"
      case "$k" in
      ssh_mode | low_ram) ;;
      *)
        printf 'error: --config %s has unsupported key: %s (allowed: modules, ssh_mode, low_ram)\n' "$custom" "$k" >&2
        return 1
        ;;
      esac
    done <"$custom"
    printf '%s\n' "$custom"
    return 0
  fi
  if [[ ! -f "$root/profiles/$profile.conf" ]]; then
    printf 'error: unknown profile: %s\n' "$profile" >&2
    return 1
  fi
  printf '%s\n' "$root/profiles/$profile.conf"
  return 0
}

# registry_require_https <url> - refuse plain http and insecure options.
registry_require_https() {
  local url="$1"
  case "$url" in
  https://*) return 0 ;;
  *)
    printf 'error: refusing non-HTTPS registry URL: %s\n' "$url" >&2
    return 1
    ;;
  esac
}

# data_entry_field <line> <field> - value of key=value token, or empty.
data_entry_field() {
  printf '%s' "$1" | grep -oE "(^| )$2=[^ ]*" | tail -n 1 | cut -d= -f2-
}

# data_entry_tier <line> - tier value, defaulting to "default" for
# entries that predate the schema (fail-open for tier, fail-closed for
# verified: see data_entry_verified).
data_entry_tier() {
  local tier
  tier="$(data_entry_field "$1" tier)"
  [[ -z "$tier" ]] && tier="default"
  printf '%s\n' "$tier"
}

# data_entry_verified <line> - 0 when the entry may be used. Entries with
# anything but verified=true are IGNORED unless the test-only override
# TEMPER_ALLOW_UNVERIFIED=1 is set together with TEMPER_TEST=1.
# Automation must NEVER set verified=true; only a human flips it after
# manual review (see docs/DATA-REVIEW.md).
data_entry_verified() {
  local val
  val="$(data_entry_field "$1" verified)"
  [[ "$val" == "true" ]] && return 0
  if [[ "${TEMPER_TEST:-0}" == "1" && "${TEMPER_ALLOW_UNVERIFIED:-0}" == "1" ]]; then
    return 0
  fi
  return 1
}

# registry_pick_url <listfile> - explicit --mirror wins (validated), else the
# first curated entry, announced loudly (never silent auto-selection).
registry_pick_url() {
  local list="$1" url="" line cand
  if [[ -n "${TEMPER_MIRROR_URL:-}" ]]; then
    url="$TEMPER_MIRROR_URL"
    printf 'mirror: explicit --mirror %s\n' "$url" >&2
  else
    # First usable curated entry: verified only, official-default origins
    # are NEVER auto-selected (reset to official via explicit --mirror URL).
    while IFS= read -r line; do
      case "$line" in
      '' | \#*) continue ;;
      esac
      data_entry_verified "$line" || continue
      [[ "$(data_entry_tier "$line")" == "official-default" ]] && continue
      cand="$(printf '%s' "$line" | awk '{print $1}')"
      if [[ -n "$cand" ]]; then
        url="$cand"
        printf 'mirror: defaulting to curated entry %s (override with --mirror URL)\n' "$url" >&2
        break
      fi
    done <"$list" 2>/dev/null
  fi
  if [[ -z "$url" ]]; then
    printf 'error: no verified registry mirror available (see docs/DATA-REVIEW.md; tests only: TEMPER_ALLOW_UNVERIFIED=1 with TEMPER_TEST=1)\n' >&2
    return 1
  fi
  registry_require_https "$url" || return 1
  printf '%s\n' "$url"
}

# registry_reachable <url> - bounded fetch check. No curl: note and pass
# (file checks already ran); unreachable URL fails for rollback.
registry_reachable() {
  local url="$1"
  if ! command -v curl >/dev/null 2>&1; then
    printf 'note: curl missing, mirror reachability unchecked\n'
    return 0
  fi
  curl -sS -o /dev/null --max-time 10 "$url" 2>/dev/null
}

profile_modules() {
  local profile="$1" file mods
  file="$(profile_file "$profile")" || return 1
  mods="$(grep -E '^modules=' "$file" | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
  local m
  # shellcheck disable=SC2086
  for m in $mods; do
    # Strip workload/ prefix segments down to the file name for --only match.
    printf '%s\n' "${m##*/}"
  done
}

# profile_env <profile> - export profile settings (ssh_mode, ...) as
# TEMPER_* vars for modules. Only simple KEY=value lines; modules= ignored.
profile_env() {
  local profile="$1" file line k v
  file="$(profile_file "$profile")" || return 1
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
    export "TEMPER_$k=$v"
  done <"$file"
  export TEMPER_PROFILE="$profile"
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
  local ran=0 want_ssh=0 want_fw=0 want_reg=0 gated=0
  local -a to_run=()
  local m
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/i18n.sh"
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
  if [[ -n "$only" ]]; then
    # --only names modules explicitly: profile gives env, list gives scope.
    local IFS=','
    for m in $only; do
      m="$(printf '%s' "$m" | tr -d ' ')"
      [[ -z "$m" ]] && continue
      if [[ ! -f "${TEMPER_ROOT:-.}/modules/$m.sh" ]]; then
        printf 'error: unknown module: %s\n' "$m" >&2
        return 1
      fi
      to_run+=("$m")
    done
  else
    # Pass 1: collect the run list from the profile (unimplemented ones
    # are skipped with a note; dangerous ones need flags below).
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      if [[ ! -f "${TEMPER_ROOT:-.}/modules/$m.sh" ]]; then
        printf 'skip: module %s is not implemented yet\n' "$m"
        continue
      fi
      to_run+=("$m")
    done < <(profile_modules "$profile")
  fi
  # Pass 2: dangerous modules are NEVER default, even via --only: explicit
  # --with-ssh / --with-firewall flags are required to enlist.
  local -a final_run=()
  for m in "${to_run[@]}"; do
    if [[ "$m" == "ssh" && "${TEMPER_WITH_SSH:-0}" != "1" ]]; then
      printf 'skip: ssh (%s)\n' "$(t need_with_ssh)"
      gated=$((gated + 1))
      continue
    fi
    if [[ "$m" == "firewall" || "$m" == "fail2ban" ]] && [[ "${TEMPER_WITH_FIREWALL:-0}" != "1" ]]; then
      printf 'skip: %s (%s)\n' "$m" "$(t need_with_firewall)"
      gated=$((gated + 1))
      continue
    fi
    if [[ "$m" == "pip_mirror" || "$m" == "npm_mirror" || "$m" == "docker_mirror" ]] && [[ "${TEMPER_WITH_REGISTRY:-0}" != "1" ]]; then
      printf 'skip: %s (%s)\n' "$m" "$(t need_with_registry)"
      gated=$((gated + 1))
      continue
    fi
    if [[ "$m" == "ssh" ]]; then want_ssh=1; fi
    if [[ "$m" == "firewall" || "$m" == "fail2ban" ]]; then want_fw=1; fi
    if [[ "$m" == "pip_mirror" || "$m" == "npm_mirror" || "$m" == "docker_mirror" ]]; then want_reg=1; fi
    final_run+=("$m")
  done
  to_run=("${final_run[@]}")
  # Pass 3: typed confirmation for dangerous modules (risks printed FIRST).
  # --yes bypasses typing (flags alone are the opt-in); anything else aborts.
  if [[ "$want_ssh" == "1" ]]; then
    printf '%s\n' "$(t risk_ssh)"
    if ! ui_type_confirm "$(t type_ssh)" "SSH-YES"; then
      printf '%s\n' "$(t aborted)"
      return 1
    fi
  fi
  if [[ "$want_fw" == "1" ]]; then
    printf '%s\n' "$(t risk_firewall)"
    if ! ui_type_confirm "$(t type_firewall)" "FIREWALL-YES"; then
      printf '%s\n' "$(t aborted)"
      return 1
    fi
  fi
  if [[ "$want_reg" == "1" ]]; then
    printf '%s\n' "$(t risk_registry)"
    if ! ui_type_confirm "$(t type_registry)" "REGISTRY-YES"; then
      printf '%s\n' "$(t aborted)"
      return 1
    fi
  fi
  # shellcheck disable=SC1091
  local id dir rc
  for m in "${to_run[@]}"; do
    module_load "$m" || return 1
    printf '=== module: %s ===\n' "$m"
    "${m}_recommend" || true
    if [[ "${TEMPER_DRY_RUN:-0}" == "1" ]]; then
      # Dry-run: show diffs only. No backup, no verify, no rollback, no log.
      "${m}_apply" "$TEMPER_STATE_DIR/backups/dry-run" || return 1
      printf 'dry-run: %s (no changes made)\n' "$m"
      ran=$((ran + 1))
      continue
    fi
    id="$(new_backup_id)"
    dir="${TEMPER_STATE_DIR:-/var/lib/temper}/backups/$id"
    mkdir -p "$dir" || return 1
    "${m}_apply" "$dir"
    rc=$?
    if [[ "$rc" == "2" ]]; then
      printf 'skip: %s has nothing to do here (see notes above)\n' "$m"
      # Own fresh dir (just mkdir'd above): rmdir, never rm -rf.
      rmdir "$dir" 2>/dev/null || true
      continue
    fi
    if [[ "$rc" -ne 0 ]]; then
      printf 'error: %s apply failed; nothing was kept\n' "$m" >&2
      return 1
    fi
    if ! "${m}_verify"; then
      printf 'error: %s health-check failed; rolling back %s\n' "$m" "$id" >&2
      rollback_id "$id" || true
      # Optional live cleanup (e.g. firewall removes only its own table).
      if declare -F "${m}_rollback_live" >/dev/null 2>&1; then
        "${m}_rollback_live" "$id" || true
      fi
      return 1
    fi
    state_log_applied "module=$m backup=$id profile=$profile"
    printf 'ok: %s applied (backup %s)\n' "$m" "$id"
    ran=$((ran + 1))
  done
  if [[ -n "$only" && "$ran" == "0" && "$gated" == "0" ]]; then
    printf 'error: --only ran nothing in profile %s: %s (unknown, skipped, or refused)\n' "$profile" "$only" >&2
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
    printf 'dns: benchmarks candidate resolvers live (latency plus failure rate) with timeouts, honors systemd-resolved/resolv.conf/netplan, respects cloud-init, rolls back when resolution breaks. Auto pool is tier default only; tier optional resolvers join solely via --dns-extra after typed disclosure, never auto-selected. DoT stays off unless --with-dot and port 853 is reachable on both winners (resolved backend only).\n'
    ;;
  mirror)
    printf 'mirror: handles sources.list AND deb822, benchmarks mirrors live, swaps only the URI, verifies with apt update; pip/npm/docker registry mirrors are opt-in file writes.\n'
    ;;
  pip_mirror)
    printf 'pip_mirror: system pip index-url from mirrors-pip.list (owner/docs per entry); tool-gated + --with-registry opt-in, HTTPS only, NOT signed like apt.\n'
    ;;
  npm_mirror)
    printf 'npm_mirror: system npm registry from mirrors-npm.list (/etc/npmrc); tool-gated + --with-registry opt-in, HTTPS only, NOT signed like apt.\n'
    ;;
  docker_mirror)
    printf 'docker_mirror: registry-mirrors merged into daemon.json preserving all keys (JSON validated, backup first); tool-gated + --with-registry opt-in, HTTPS only, NOT signed like apt; warns restart affects containers, never restarts automatically.\n'
    ;;
  ssh)
    printf 'ssh: ADMIN (key-only after verified key, deferred lockdown on confirm), TUNNEL (restricted user, client artifacts), CUSTOM (validated snippet). Drop-in sorts first; guard + NEW-session confirm; --with-ssh required.\n'
    ;;
  firewall)
    printf 'firewall: ufw (allow-before-enable, IPV6=yes) or nftables (own table, atomic). Default-deny only under guard. Docker bypasses ufw. --with-firewall required.\n'
    ;;
  fail2ban)
    printf 'fail2ban: jail.d drop-in, session source in ignoreip, backend=systemd. Runs with --with-firewall.\n'
    ;;
  security | cleanup | docker | nginx | db)
    printf '%s: planned module, not implemented yet.\n' "$1"
    ;;
  *)
    printf 'error: unknown module: %s\n' "$1" >&2
    return 1
    ;;
  esac
}
