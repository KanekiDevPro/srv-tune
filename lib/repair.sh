#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Repair command: replay the health checks, then re-apply ONLY the drifted
# modules with the profile recorded at apply time, using the apply rails
# (backup -> apply -> verify -> auto-rollback). Write command: needs root
# (or TEMPER_SYSROOT for sandboxed tests).
# Exit: 0 nothing-to-repair / repaired / dry-run ok; 1 not repairable or
# apply failed; 2 root/preflight/missing-profile-record problems.
# shellcheck shell=bash

if [[ -n "${__TEMPER_REPAIR_SOURCED:-}" ]]; then
  return 0
fi
__TEMPER_REPAIR_SOURCED=1

# repair_recorded_profile <log> <module> - profile from the module's most
# recent applied-changes line, or empty when its lines predate profile
# recording (or the module was never applied with one).
repair_recorded_profile() {
  sed -n "s/^.*module=$2 .*profile=\([^ ]*\)\$/\1/p" "$1" | tail -n 1
}

# repair_run - doctor, then repair only what is broken.
repair_run() {
  local root="${TEMPER_ROOT:-.}"
  # shellcheck disable=SC1091
  source "$root/lib/util.sh"
  # shellcheck disable=SC1091
  source "$root/lib/lock.sh"
  # shellcheck disable=SC1091
  source "$root/lib/health.sh"
  # shellcheck disable=SC1091
  source "$root/lib/modules.sh"
  local base log m r st name rp="" p gated=0 only="" rc=0 hrc=0
  local -a failed=() repairable=()
  base="${TEMPER_STATE_DIR:-/var/lib/temper}"
  log="$base/applied-changes.log"

  if ! is_root && [[ "${TEMPER_SYSROOT:-/}" == "/" ]]; then
    printf 'error: repair needs root (or TEMPER_SYSROOT for sandboxed tests)\n' >&2
    return 2
  fi

  # Fresh replay state, then the same read-only checks health runs.
  __HEALTH_ROWS=()
  __HEALTH_PASSES=0
  __HEALTH_WARNS=0
  __HEALTH_FAILS=0
  __HEALTH_SKIPS=0
  health_run || hrc=$?

  for r in "${__HEALTH_ROWS[@]}"; do
    st="${r%%|*}"
    [[ "$st" == "FAIL" ]] || continue
    name="${r#*|}"
    name="${name%%|*}"
    case "$name" in
    module:*) failed+=("${name#module:}") ;;
    esac
  done

  if [[ "${#failed[@]}" -eq 0 ]]; then
    printf 'repair: nothing to repair\n'
    return "$hrc"
  fi

  # Gated modules stay gated: repair never bypasses an opt-in flag.
  for m in "${failed[@]}"; do
    if [[ ! -f "$root/modules/$m.sh" ]]; then
      printf 'repair: %s is not in this build; cannot repair\n' "$m"
      continue
    fi
    case "$m" in
    ssh)
      if [[ "${TEMPER_WITH_SSH:-0}" != "1" ]]; then
        printf 'repair: %s needs --with-ssh\n' "$m"
        gated=$((gated + 1))
        continue
      fi
      ;;
    firewall | fail2ban)
      if [[ "${TEMPER_WITH_FIREWALL:-0}" != "1" ]]; then
        printf 'repair: %s needs --with-firewall\n' "$m"
        gated=$((gated + 1))
        continue
      fi
      ;;
    pip_mirror | npm_mirror | docker_mirror)
      if [[ "${TEMPER_WITH_REGISTRY:-0}" != "1" ]]; then
        printf 'repair: %s needs --with-registry\n' "$m"
        gated=$((gated + 1))
        continue
      fi
      ;;
    esac
    repairable+=("$m")
  done
  if [[ "${#repairable[@]}" -eq 0 ]]; then
    printf 'repair: nothing repairable (%s gated, %s unhealthy module(s) total)\n' \
      "$gated" "${#failed[@]}"
    return 1
  fi

  # One profile per run: every drifted module must agree on its recorded
  # profile, else the repair is ambiguous and stays explicit.
  for m in "${repairable[@]}"; do
    p="$(repair_recorded_profile "$log" "$m")"
    if [[ -z "$p" ]]; then
      printf 'error: no recorded profile for module %s (applied before profile recording); re-apply it explicitly: apply --profile <name> --only %s\n' "$m" "$m" >&2
      return 2
    fi
    if [[ -z "$rp" ]]; then
      rp="$p"
    elif [[ "$rp" != "$p" ]]; then
      printf 'error: drifted modules recorded different profiles (%s vs %s for %s); re-apply explicitly, one profile at a time\n' \
        "$rp" "$p" "$m" >&2
      return 2
    fi
  done
  if [[ "$rp" == "custom" && -z "${TEMPER_CUSTOM_PROFILE:-}" ]]; then
    printf 'error: custom profile recorded; pass the same --config file again\n' >&2
    return 2
  fi

  only="$(printf '%s\n' "${repairable[@]}" | paste -sd, -)"
  printf 'repair plan: profile=%s modules=%s\n' "$rp" "$only"
  printf 'each module: backup -> apply -> verify (any failure rolls back)\n'

  if ! preflight_check; then
    printf 'error: preflight blocks repair (see above)\n' >&2
    return 2
  fi

  if [[ "${TEMPER_DRY_RUN:-0}" == "1" ]]; then
    # Dry-run: exact per-module diffs via the apply pipeline, no writes.
    rc=0
    run_apply "$rp" "$only" || rc=$?
    printf 'repair: dry-run complete (no changes made)\n'
    return "$rc"
  fi

  # shellcheck disable=SC1091
  source "$root/lib/ui.sh"
  lock_acquire || return 1
  trap lock_release EXIT INT TERM
  rc=0
  if ! ui_confirm_default_yes "Re-apply drifted modules: $only (profile $rp)?"; then
    printf 'aborted\n'
    rc=1
  else
    run_apply "$rp" "$only" || rc=$?
  fi
  trap - EXIT INT TERM
  lock_release
  return "$rc"
}
