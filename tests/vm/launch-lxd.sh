#!/usr/bin/env bash
# Launch LXD VM for systemd tests.
# Usage: tests/vm/launch-lxd.sh [ubuntu:24.04]
# shellcheck shell=bash
set -euo pipefail
IMG="${1:-ubuntu:24.04}"
lxc launch "$IMG" srv-tune-test --vm -c limits.memory=2GB
sleep 15
lxc file push -r . srv-tune-test/tmp/srv-tune/
lxc exec srv-tune-test -- bash /tmp/srv-tune/tests/run-in-vm.sh
