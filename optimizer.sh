#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# srv-tune entrypoint: SCAN -> RECOMMEND -> APPLY -> VERIFY -> ROLLBACK-IF-BROKEN.
# shellcheck shell=bash
set -euo pipefail

SRV_TUNE_ROOT="${BASH_SOURCE[0]}"
# Resolve install symlinks (prefix/bin/srv-tune -> share/srv-tune) without
# readlink -f (not portable): follow one level at a time, bounded.
for _i in 1 2 3 4 5 6 7 8; do
  if [[ -L "$SRV_TUNE_ROOT" ]]; then
    _tgt="$(readlink "$SRV_TUNE_ROOT")"
    case "$_tgt" in
    /*) SRV_TUNE_ROOT="$_tgt" ;;
    *) SRV_TUNE_ROOT="$(dirname "$SRV_TUNE_ROOT")/$_tgt" ;;
    esac
  else
    break
  fi
done
unset _i _tgt
SRV_TUNE_ROOT="$(cd "$(dirname "$SRV_TUNE_ROOT")" && pwd)"
export SRV_TUNE_ROOT

# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/log.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/ui.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/i18n.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/lock.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/state.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/rollback.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/preflight.sh"
# shellcheck disable=SC1091
source "$SRV_TUNE_ROOT/lib/ssh-guard.sh"

VERSION="$(cat "$SRV_TUNE_ROOT/VERSION" 2>/dev/null || printf '0.1.0')"

usage() {
  cat <<EOF
srv-tune $VERSION — Linux server optimizer
Usage:
  optimizer scan [--json FILE] [--lang fa|en]
  optimizer recommend [--lang fa|en]
  optimizer apply --profile X [--only mod[,mod]] [--dry-run] [--yes] [--lang fa|en]
  optimizer rollback [id] | list-backups | status | explain <module>
  optimizer benchmark [--out DIR] [--iperf-server H] [--install-deps]
  optimizer benchmark --compare BEFORE AFTER [--format md|json|html]
  optimizer audit | update | uninstall | confirm <guard-id> [--force]
  optimizer ssh-close-port <port> (explicit; only after NEW-session proof)
  optimizer --help | --version
EOF
}

PROFILE=""
DRY_RUN="${SRV_TUNE_DRY_RUN:-0}"
ASSUME_YES="${SRV_TUNE_ASSUME_YES:-0}"
FORCE=0
JSON_OUT=""
ONLY=""
CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  scan | recommend | apply | rollback | list-backups | status | benchmark | explain | audit | update | uninstall | confirm | ssh-close-port)
    CMD="$1"
    shift
    if [[ "$CMD" == "explain" || "$CMD" == "rollback" || "$CMD" == "confirm" || "$CMD" == "ssh-close-port" ]]; then
      EXTRA="${1:-}"
      shift || true
      export EXTRA
    fi
    ;;
  --out)
    BENCH_OUT="${2:-bench-out}"
    export BENCH_OUT
    shift 2
    ;;
  --iperf-server)
    BENCH_IPERF="${2:-}"
    export BENCH_IPERF
    shift 2
    ;;
  --install-deps)
    export SRV_TUNE_INSTALL_DEPS=1
    shift
    ;;
  --compare)
    BENCH_CMP_A="${2:-}"
    BENCH_CMP_B="${3:-}"
    export BENCH_CMP_A BENCH_CMP_B
    shift 3 2>/dev/null || {
      printf 'error: --compare needs BEFORE AFTER files\n' >&2
      exit 2
    }
    ;;
  --format)
    BENCH_FORMAT="${2:-md}"
    export BENCH_FORMAT
    shift 2
    ;;
  --profile)
    PROFILE="${2:-}"
    shift 2
    ;;
  --only)
    ONLY="${2:-}"
    shift 2
    ;;
  --with-ssh)
    export SRV_TUNE_WITH_SSH=1
    shift
    ;;
  --with-firewall)
    export SRV_TUNE_WITH_FIREWALL=1
    shift
    ;;
  --with-registry)
    export SRV_TUNE_WITH_REGISTRY=1
    shift
    ;;
  --mirror)
    export SRV_TUNE_MIRROR_URL="${2:-}"
    shift 2
    ;;
  --dns-extra)
    if [[ -z "${SRV_TUNE_DNS_EXTRA:-}" ]]; then
      export SRV_TUNE_DNS_EXTRA="${2:-}"
    else
      export SRV_TUNE_DNS_EXTRA="${SRV_TUNE_DNS_EXTRA},${2:-}"
    fi
    shift 2
    ;;
  --with-dot)
    export SRV_TUNE_WITH_DOT=1
    shift
    ;;
  --config)
    export SRV_TUNE_CUSTOM_PROFILE="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=1
    export SRV_TUNE_DRY_RUN="$DRY_RUN"
    shift
    ;;
  --yes)
    ASSUME_YES=1
    export SRV_TUNE_ASSUME_YES="$ASSUME_YES"
    shift
    ;;
  --force)
    FORCE=1
    shift
    ;;
  --lang)
    SRV_TUNE_LANG="${2:-en}"
    export SRV_TUNE_LANG
    shift 2
    ;;
  --json)
    JSON_OUT="${2:-}"
    shift 2
    ;;
  --version | -V)
    printf 'srv-tune %s\n' "$VERSION"
    exit 0
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    printf 'error: unknown arg: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

[[ -z "$CMD" ]] && {
  usage >&2
  exit 2
}

# cmd_locked_scan [extra args...] - lock, trap, scan, release. Read-only.
cmd_locked_scan() {
  lock_acquire || exit 1
  # EXIT covers normal + error paths; INT/TERM cover Ctrl+C and kill.
  # lock_release is idempotent, so double runs are safe.
  trap lock_release EXIT INT TERM
  bash "$SRV_TUNE_ROOT/scanner/scan.sh" "$@"
  local rc=$?
  trap - EXIT INT TERM
  lock_release
  exit $rc
}

case "$CMD" in
scan)
  export SRV_TUNE_JSON_OUT="$JSON_OUT"
  cmd_locked_scan
  ;;
recommend)
  cmd_locked_scan --recommend-only
  ;;
audit)
  # Report only: preflight warnings never block the read-only scan.
  preflight_check || log_warn "preflight issues noted (audit continues read-only)"
  export SRV_TUNE_JSON_OUT="$JSON_OUT"
  cmd_locked_scan --recommend-only
  ;;
apply)
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  if [[ -z "$PROFILE" ]]; then
    # Interactive selection, default = scanner recommendation (One Enter).
    # --yes without --profile takes the recommendation silently.
    rec="$(bash "$SRV_TUNE_ROOT/scanner/scan.sh" --recommend-only 2>/dev/null | awk '/^profile:/{print $2}' || true)"
    [[ -z "$rec" ]] && rec="generic"
    PROFILE="$(ui_menu "$(t choose_profile)" "$rec" generic web database docker vpn-tunnel low-ram custom)"
  fi
  if ! preflight_check; then
    printf 'error: preflight blocks apply (see above)\n' >&2
    exit 2
  fi
  lock_acquire || exit 1
  trap lock_release EXIT INT TERM
  if ! ui_confirm_default_yes "Apply profile $PROFILE${ONLY:+ (only: $ONLY)}?"; then
    printf 'aborted\n'
    trap - EXIT INT TERM
    lock_release
    exit 1
  fi
  run_apply "$PROFILE" "$ONLY"
  rc=$?
  trap - EXIT INT TERM
  lock_release
  exit $rc
  ;;
rollback)
  rollback_id "${EXTRA:-}"
  ;;
list-backups)
  rollback_list
  ;;
status)
  preflight_os_id
  preflight_os_version
  preflight_os_tier
  ;;
confirm)
  guard_confirm "${EXTRA:-}" "$FORCE"
  ;;
ssh-close-port)
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_load ssh
  lock_acquire || exit 1
  trap lock_release EXIT INT TERM
  ssh_close_port "${EXTRA:-}"
  rc=$?
  trap - EXIT INT TERM
  lock_release
  exit $rc
  ;;
explain)
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/modules.sh"
  module_explain "${EXTRA:-}"
  ;;
benchmark)
  if [[ -n "${BENCH_CMP_A:-}" ]]; then
    bash "$SRV_TUNE_ROOT/bench/compare.sh" "$BENCH_CMP_A" "$BENCH_CMP_B" --format="${BENCH_FORMAT:-md}"
    exit $?
  fi
  args=("$SRV_TUNE_ROOT/bench/bench.sh" "${BENCH_OUT:-bench-out}")
  if [[ -n "${BENCH_IPERF:-}" ]]; then
    args+=("--iperf-server=$BENCH_IPERF")
  fi
  if [[ "${SRV_TUNE_INSTALL_DEPS:-0}" == "1" ]]; then
    args+=("--install-deps")
  fi
  bash "${args[@]}"
  ;;
update)
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/update.sh"
  self_update
  ;;
uninstall)
  # shellcheck disable=SC1091
  source "$SRV_TUNE_ROOT/lib/update.sh"
  do_uninstall "${SRV_TUNE_PREFIX:-/usr/local}"
  ;;
esac
