#!/usr/bin/env bash
# srv-tune entrypoint: SCAN -> RECOMMEND -> APPLY -> VERIFY -> ROLLBACK-IF-BROKEN.
# shellcheck shell=bash
set -euo pipefail

SRV_TUNE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  optimizer apply --profile X [--dry-run] [--yes] [--lang fa|en]
  optimizer rollback [id] | list-backups | status | benchmark | explain <module>
  optimizer audit | update | uninstall | confirm <guard-id> [--force]
  optimizer --help | --version
EOF
}

PROFILE=""
DRY_RUN=0
ASSUME_YES=0
FORCE=0
JSON_OUT=""
CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    scan|recommend|apply|rollback|list-backups|status|benchmark|explain|audit|update|uninstall|confirm)
      CMD="$1"; shift
      if [[ "$CMD" == "explain" || "$CMD" == "rollback" || "$CMD" == "confirm" ]]; then
        EXTRA="${1:-}"; shift || true
        export EXTRA
      fi
      ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; export SRV_TUNE_ASSUME_YES=1; shift ;;
    --force) FORCE=1; shift ;;
    --lang) SRV_TUNE_LANG="${2:-en}"; export SRV_TUNE_LANG; shift 2 ;;
    --json) JSON_OUT="${2:-}"; shift 2 ;;
    --version|-V) printf 'srv-tune %s\n' "$VERSION"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -z "$CMD" ]] && { usage >&2; exit 2; }

case "$CMD" in
  scan)
    lock_acquire || exit 1
    export SRV_TUNE_JSON_OUT="$JSON_OUT"
    bash "$SRV_TUNE_ROOT/scanner/scan.sh"
    rc=$?
    lock_release
    exit $rc
    ;;
  recommend)
    lock_acquire || exit 1
    bash "$SRV_TUNE_ROOT/scanner/scan.sh" --recommend-only
    rc=$?
    lock_release
    exit $rc
    ;;
  apply)
    [[ -z "$PROFILE" ]] && { printf 'error: apply requires --profile X\n' >&2; exit 2; }
    printf 'apply --profile %s is MVP-blocked (P3). Scanner + safety engine only in v0.1.\n' "$PROFILE" >&2
    exit 3
    ;;
  rollback)
    rollback_id "${EXTRA:-}" ;;
  list-backups)
    rollback_list ;;
  status)
    preflight_os_id; preflight_os_version; preflight_os_tier ;;
  confirm)
    guard_confirm "${EXTRA:-}" "$FORCE" ;;
  explain|audit|benchmark|update|uninstall)
    printf '%s: not yet implemented in v0.1 (MVP = scanner + backup/rollback)\n' "$CMD" >&2
    exit 3
    ;;
esac
