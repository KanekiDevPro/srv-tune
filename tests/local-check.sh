#!/usr/bin/env bash
set -u
fail=0
for f in optimizer.sh lib/common.sh lib/log.sh lib/ui.sh lib/i18n.sh lib/i18n/en.sh lib/i18n/fa.sh lib/lock.sh lib/state.sh lib/backup.sh lib/rollback.sh lib/util.sh lib/preflight.sh lib/health.sh lib/ssh-guard.sh lib/update.sh lib/detect.sh scanner/scan.sh scanner/report.sh scanner/collectors/os.sh scanner/collectors/hw.sh scanner/collectors/net.sh scanner/collectors/ssh.sh scanner/collectors/fw.sh tests/bats_helper.bash tests/run-in-vm.sh tests/vm/launch-multipass.sh tests/vm/launch-lxd.sh; do
  if bash -n "$f"; then
    echo "OK $f"
  else
    echo "FAIL $f"
    fail=1
  fi
done
echo "--- scan smoke ---"
SRV_TUNE_STATE_DIR=/tmp/srv-tune-test-state bash scanner/scan.sh --recommend-only || fail=1
echo "--- backup smoke ---"
export SRV_TUNE_STATE_DIR=/tmp/srv-tune-test-state
mkdir -p /tmp/srv-tune-test-state/backups
echo v1 >/tmp/srv-orig.conf
bash -c 'source lib/backup.sh; source lib/rollback.sh; backup_file /tmp/srv-orig.conf /tmp/srv-tune-test-state/backups/t1; echo v2 > /tmp/srv-orig.conf; rollback_id t1; cat /tmp/srv-orig.conf'
test "$(cat /tmp/srv-orig.conf)" = "v1" || fail=1
exit $fail
