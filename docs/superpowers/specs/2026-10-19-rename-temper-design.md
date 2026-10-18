# Rename: srv-tune → Temper — Design

- Date: 2026-10-19
- Status: approved in chat (approach A: clean rename, no compatibility layer)
- Scope: repository-wide textual rename + repo rename; no product-semantics change
- Follow-up: implementation plan (docs/superpowers/plans/) → single rename PR → repo rename

## Goal

Give the project a distinct, professional identity: **Temper** — tempering is a
controlled hardening process (heat, then controlled cooling), which matches the
product's SCAN → RECOMMEND → APPLY → VERIFY → ROLLBACK-IF-BROKEN story.

## Name verification (2026-10-19)

- Ubuntu/Debian packages: no `temper` binary. Only USB-thermometer libraries
  (`libdevice-usb-pcsensor-hidtemper-perl`, `python3-temperusb`).
- GitHub: no server-admin CLI named temper. Closest hits: `temperlang/temper`
  (programming language, ~325 stars), `EnsoBuild/temper` (Ethereum transaction
  simulator, ~371 stars), a split keyboard, an audio plugin — different domains.
- Rejected candidates and why: `warden` (three or more existing CLIs), `drydock`
  (host provisioning tool + git TUI + terminal agent), `steward`, `attune` (Linux
  package publishing), `fettle` (Linux system-maintenance tool), `vigil` (monitor
  CLI + language).

## Decisions

1. **Approach A — clean rename.** No `srv-tune` wrapper, no state migration, no
   runtime fallback. Rationale: the repository went public 2026-10-18; real external
   users ≈ 0; a permanent dual-name layer is maintenance for nobody.
2. **History is not rewritten.** Old CHANGELOG sections keep `srv-tune` — they
   describe releases that shipped under that name (CHANGELOG.md lines 7, 17, 43).
3. **Version.** `VERSION` 0.4.0 → 0.5.0 in the rename PR (fresh identity = next
   minor). The CHANGELOG keeps its `## Unreleased` heading until the release-prep PR
   dates it (same flow as v0.4.0). Tag and publish are explicit user instructions,
   after the repo rename.
4. **Working docs are renamed; release records are not.** Feature docs under
   `docs/` (including `docs/superpowers/` design/plan docs from earlier work)
   document features that still exist → mechanically renamed. Exception: the rename
   design/plan docs themselves (see Exceptions).
5. **Runtime paths renamed.** State dir `/var/lib/temper`, sshd drop-ins
   `00-temper*.conf`.

## Mapping

Case-sensitive, applied in this order.

| From | To | Approx. count |
| --- | --- | --- |
| `SRV_TUNE` (env vars, `__SRV_TUNE_*_SOURCED` guards, `SRV_TUNE_NAME`) | `TEMPER` | 1755 |
| `srv-tune` | `temper` | 492 |
| `srv_tune` | `temper` | 36 |
| `SRV-TUNE` (man page `.TH`) | `TEMPER` | 2 |
| `/var/lib/srv-tune` | `/var/lib/temper` | included above |
| `00-srv-tune*.conf` | `00-temper*.conf` | included above |
| `docs/srv-tune.1` → `docs/temper.1`; `completion/srv-tune.bash` → `completion/temper.bash` | `git mv` + content | 2 files |
| Release assets `srv-tune-${TAG}.tar.gz` → `temper-${TAG}.tar.gz` | release.yml | included above |
| URLs/badges `github.com/KanekiDevPro/srv-tune` → `.../temper` | README ×2, docs, install one-liner | included above |
| `SRV_TUNE_NAME="srv-tune"` (lib/common.sh) | `TEMPER_NAME="temper"` | 1 |

Files: 98 total — tests 44, lib 20, modules 11, docs 5, scanner 3, templates 2,
bench 2, web 1, schema 1; root: optimizer.sh, install.sh, completion/,
LICENSE, README.md, README.fa.md, CHANGELOG.md, SECURITY.md,
.github/workflows/release.yml.

## Exceptions (must stay `srv-tune`)

- CHANGELOG.md historical lines 7, 17, 43 (v0.2–v0.4 sections).
- The new "formerly srv-tune" lines in README.md and README.fa.md.
- The new CHANGELOG `## Unreleased` bullet naming the old name.
- The new dated status row in docs/VERIFICATION-DEBT.md.
- **This design doc and its implementation plan doc** — they describe the rename and
  quote the old name by necessity. The rename script must exclude them from `sed`.

## Execution

1. Branch `v0.5/rename-temper` from master.
2. Mechanical rename script with the mapping above (exceptions excluded; `git mv`
   for the two renamed files).
3. Hand edits:
   - CHANGELOG `## Unreleased` entry (rename + formerly).
   - README.md / README.fa.md "formerly" line.
   - docs/VERIFICATION-DEBT.md dated row (evidence-based, added when the PR is green).
   - `VERSION` → 0.5.0; `docs/temper.1` `.TH` version string → `temper 0.5.0`;
     `install.sh` pinned example → `v0.5.0`.
4. Local checks: `bats tests/`, `tests/hygiene.sh`, `tests/pre-publish.sh`.
5. One-off grep guard (not committed as a permanent test — see Out of scope):
   `git grep -i -E 'srv[-_]tune'` must return only the enumerated exceptions.
6. PR → CI green (lint-test, hygiene, uutils-check, integration ×2, scan-matrix) →
   merge under branch protection.
7. `gh repo rename temper` + `git remote set-url origin .../temper.git`; verify:
   - `curl -sI https://github.com/KanekiDevPro/srv-tune` → 301 to `.../temper`.
   - Raw badge URL under the new name → 200.
   - `gh repo view --json name` = `temper`; branch protection still reports its
     contexts; repository description/topics contain no old name.
8. Release path smoke test: `gh workflow run release.yml -f dry-run=true` →
   artifact must be named `temper-dry-run-<sha>.tar.gz`.
9. Later, on explicit instruction: release-prep PR dates the CHANGELOG section →
   tag `v0.5.0` → publish (same flow as v0.4.0).

## Verification / success criteria

- Guard grep returns only the enumerated exceptions.
- Full CI green on the rename PR and on master after the merge.
- Old repo URL redirects 301 to the new one; every in-repo URL points at the new name.
- Dry-run release artifact carries the `temper-` prefix.
- No test deleted or weakened; the suite changes only in renamed identifiers and
  paths. The existing bats suite is the regression test for this rename.

## Out of scope / rejected

- `srv-tune` compatibility wrapper (approach C) — rejected (decision 1).
- Migrating `/var/lib/srv-tune` state or old drop-ins on existing hosts — README
  cleanup note only; old artifacts become orphans.
- Re-publishing old releases under new asset names — old assets stay as shipped;
  pinned installs of old versions keep working via that tag's own `install.sh`.
- A permanent grep-guard test — brittle against the enumerated history; the one-off
  check is documented in the rename PR instead.

## Risks

- `raw.githubusercontent.com` redirects after a repo rename are not guaranteed → all
  in-repo URLs are updated in the same PR; the window between the merge and
  `gh repo rename` is seconds.
- Branch protection and CI contexts depend on job names, not the repository name →
  unaffected by the rename.
- Old releases keep `srv-tune-*` asset names (historical, acceptable).
