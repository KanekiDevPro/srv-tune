#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Launch LXD VM for systemd tests.
# Usage: tests/vm/launch-lxd.sh [ubuntu:24.04]
# shellcheck shell=bash
set -euo pipefail
IMG="${1:-ubuntu:24.04}"
lxc launch "$IMG" temper-test --vm -c limits.memory=2GB
sleep 15
lxc file push -r . temper-test/tmp/temper/
lxc exec temper-test -- bash /tmp/temper/tests/run-in-vm.sh
