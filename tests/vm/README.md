# VM tests need real systemd (ssh.socket, systemd-run guard).
# Multipass and LXD scripts above cover this. Plain Docker is NOT enough.
# run-in-vm.sh runs: shellcheck + bats tests/ (excluding vm/).
