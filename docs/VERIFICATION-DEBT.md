# VERIFICATION-DEBT — what is NOT yet proven (Round 2)

This file tracks verification gaps. Entries leave only with fresh evidence
(CI link or manual-review signature), never by assertion.

## Open

- [ ] DATA-REVIEW rows 1-18: all `verified=pending`. Owner/docs URLs are
  written from memory, none fetched. Release is gated until a human reviews
  (`tests/pre-publish.sh`, `release.yml`).
- [ ] 185.51.200.2 ownership conflict (was `electrotm`, third-party README
  says Shecan secondary). Relabeled `unknown-owner (conflict)`, pending.
  See `docs/DATA-REVIEW.md` row 6.
- [ ] `release.yml` pending-gate never fired on a real tag push (runs only on
  `v*.*.*`). Next release attempt will exercise it (expected FAIL while
  entries are pending — that is the gate working).
- [ ] `tests/pre-publish.sh` also reports pre-existing environment findings
  unrelated to this branch (secret-like content in tree, key material in
  history, local username in paths). Triage separately; do NOT weaken the
  `verified=pending` gate to silence them.
- [ ] Full `bats tests/` suite times out on Windows dev hosts; Linux CI is
  the source of truth (`lint-test` + `uutils-check` jobs).
- [ ] DoT offer path and netplan apply path in `modules/dns.sh` are covered
  only where tests reach them; dedicated DoT/netplan work is tracked as the
  Round 2 dns item, not here.
  DONE (Round 2 dns item, this branch): DoT probe + recommend offer,
  `--with-dot` fail-closed on resolved backend only, netplan backend test.

## Reconciliation warning

- [ ] `docs/VERIFICATION-DEBT.md` also exists on unmerged branch
  `v0.2/verification-docs` (open PR #4). This file was created independently
  on `v0.2/data-hardening`. At merge time the two versions must be reconciled
  by hand — do NOT auto-resolve in favor of either side.

## Closed

- (none yet this round)
