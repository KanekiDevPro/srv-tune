#!/usr/bin/env bash
# Runs inside a real VM with systemd.
# shellcheck shell=bash
set -euo pipefail
cd "$(dirname "$0")/.."
shellcheck optimizer.sh lib/*.sh lib/i18n/*.sh scanner/*.sh scanner/collectors/*.sh || exit 1
bats tests/ || exit 1
bash scanner/scan.sh --recommend-only
