#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -u
fail=0
while IFS= read -r f; do
  case "$f" in
  # .bats uses the @test idiom: parsed by bats and shellcheck, not bash -n.
  *.sh | *.bash) ;;
  *) continue ;;
  esac
  if bash -n "$f"; then
    echo "OK $f"
  else
    echo "FAIL $f"
    fail=1
  fi
done < <(git ls-files)
echo "--- scan smoke ---"
TEMPER_STATE_DIR=/tmp/temper-test-state bash scanner/scan.sh --recommend-only || fail=1
echo "--- backup smoke ---"
export TEMPER_STATE_DIR=/tmp/temper-test-state
mkdir -p /tmp/temper-test-state/backups
echo v1 >/tmp/srv-orig.conf
bash -c 'source lib/backup.sh; source lib/rollback.sh; backup_file /tmp/srv-orig.conf /tmp/temper-test-state/backups/t1; echo v2 > /tmp/srv-orig.conf; rollback_id t1; cat /tmp/srv-orig.conf'
test "$(cat /tmp/srv-orig.conf)" = "v1" || fail=1
exit $fail
