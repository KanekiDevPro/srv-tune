#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Launch Multipass VM for systemd tests (needs systemd; containers lack it).
# Usage: tests/vm/launch-multipass.sh [ubuntu-24.04|ubuntu-22.04]
# shellcheck shell=bash
set -euo pipefail
IMG="${1:-24.04}"
multipass launch "$IMG" --name srv-tune-test --disk 10G --memory 2G
multipass transfer . srv-tune-test:/tmp/srv-tune
multipass exec srv-tune-test -- bash /tmp/srv-tune/tests/run-in-vm.sh
