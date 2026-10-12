# Contributing

- Bash only, defensive and ShellCheck-clean (`shellcheck -S warning`).
- POSIX-aware: no GNU-only flags (the 26.04 jobs run uutils coreutils).
- Every behavior change ships with a bats test (RED first, watched fail).
- Run before pushing: `bash tests/hygiene.sh`, ShellCheck, `shfmt -d -i 2`,
  `bats tests/`.
- Commits: Conventional Commits, English. Code/comments/logs English; UI
  strings go through `lib/i18n` (fa + en, keys must match).
- Never touch sshd/firewall behavior without the guard + rollback path, and
  never weaken CI to make it green (no skips, no `continue-on-error`).
- Work on branches; open PRs to the default branch.
