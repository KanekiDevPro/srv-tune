# Rename to Temper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the project identity `srv-tune` → `Temper` across the whole tree (code, tests, packaging, docs) and the GitHub repository, with no compatibility layer, then verify the live redirects and the release path.

**Architecture:** One branch (`v0.5/rename-temper`) with three commits: plan → mechanical rename (scripted, case-sensitive, history excluded) → identity records. The existing bats suite is the regression test; a one-off guard grep is the completeness test. After merge: repo rename via API, live URL/redirect checks, dry-run release smoke test; evidence recorded as a comment on the merged PR.

**Tech Stack:** Git for Windows bash + `sed`, git, bats (existing suite + local shims), GitHub CLI (`gh`), `curl`.

**Spec:** `docs/superpowers/specs/2026-10-19-rename-temper-design.md`

## Global Constraints

- Mapping, case-sensitive, exactly these four rules (no other spellings exist — verified 2026-10-19):
  `SRV_TUNE`→`TEMPER`, `srv-tune`→`temper`, `srv_tune`→`temper`, `SRV-TUNE`→`TEMPER`.
- Excluded from any rewrite (must keep `srv-tune`): `CHANGELOG.md`, the rename spec doc, this plan doc.
- Runtime identity produced by the rename: binary `temper` (entry `optimizer.sh`), env prefix `TEMPER_*` (esp. `TEMPER_ROOT`), state `/var/lib/temper`, sshd drop-ins `00-temper*.conf`, man `temper(1)`, `completion/temper.bash`, release asset `temper-<tag>.tar.gz`.
- No `srv-tune` alias/wrapper, no state migration code.
- `VERSION` → `0.5.0`; CHANGELOG heading stays `## Unreleased` (dated later by a release-prep PR — out of scope here).
- No test may be deleted, skipped, or weakened; only identifiers/paths inside tests change.
- Everything lands via PR; branch protection requires green `lint-test`, `hygiene`, `uutils-check`, `integration (ubuntu-22.04)`, `integration (ubuntu-24.04)` with the branch up to date.
- Run all commands from the repo root in Git bash (Windows PowerShell mangles quoted shells; use script files under `%TEMP%\opencode` as in prior sessions). Helper: `run-bats.sh`, `master-watch.sh` in that directory.

## File Structure (rename groups)

| Group | Files | Owner task |
| --- | --- | --- |
| Core code | `lib/` (20), `modules/` (11), `scanner/` (3), `web/` (1), `schema/` (1), `templates/` (2), `bench/` (2), `optimizer.sh` | Task 1 |
| Tests | `tests/` (44, incl. `test_docs.bats`) | Task 1 |
| Packaging | `install.sh`, `completion/srv-tune.bash`→`temper.bash`, `docs/srv-tune.1`→`temper.1`, `.github/workflows/release.yml` | Task 1 |
| Docs/identity | `README.md`, `README.fa.md`, `LICENSE`, `SECURITY.md` | Task 1 (name) + Task 2 (formerly lines) |
| Records | `VERSION`, `CHANGELOG.md`, `docs/VERIFICATION-DEBT.md` | Task 2 |

## Review Focus

- Overlapping replacements mangling identifiers (`TEMPER_TEMPER`, `temper_tune`, half-renamed env names); guard: Task 1 step 4 greps for compounding artifacts.
- Missed occurrences outside the known 99 tracked files (sed rewrites 96: all but `CHANGELOG.md`, the rename spec, and this plan); guard: Task 3 step 1 repo-wide guard grep, no path filter except the documented exclusions.
- File renames breaking references (man install path, completion install path, doc/test pins); guard: Task 1 step 5 runs the full suite incl. `test_docs.bats` which pins `temper $(cat VERSION)` and the install paths.
- History lines rewritten (CHANGELOG lines 7, 17, 43); guard: Task 2 step 6 verifies they still read `srv-tune`.
- URLs left on the old repo name (raw redirects not guaranteed); guard: Task 4 step 4 greps for `KanekiDevPro/srv-tune` and curls the new raw URL.

---

### Task 1: Branch, plan commit, mechanical rename

**Files:** all tree files containing the name except `CHANGELOG.md` and the two rename docs. Renames: `docs/srv-tune.1` → `docs/temper.1`, `completion/srv-tune.bash` → `completion/temper.bash`.
**Interfaces — Produces:** fully renamed working tree; `TEMPER_NAME="temper"` (lib/common.sh), env prefix `TEMPER_*`, drop-in names `00-temper*.conf`, asset prefix `temper-` in `release.yml`.

- [ ] **Step 1: Branch from master** (the uncommitted plan doc travels along)

```bash
git checkout -b v0.5/rename-temper
git add docs/superpowers/plans/2026-10-19-rename-temper.md
git commit -m "docs(plan): rename to Temper implementation plan"
```

- [ ] **Step 2: Write the rename script** to `%TEMP%\opencode\rename-temper.sh` with exactly this content:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "${REPO_ROOT:?export REPO_ROOT to the repo checkout first}"
while IFS= read -r f; do
  case "$f" in
    CHANGELOG.md) continue ;;
    docs/superpowers/specs/2026-10-19-rename-temper-design.md) continue ;;
    docs/superpowers/plans/2026-10-19-rename-temper.md) continue ;;
  esac
  sed -i -e 's/SRV_TUNE/TEMPER/g' -e 's/srv-tune/temper/g' \
         -e 's/srv_tune/temper/g' -e 's/SRV-TUNE/TEMPER/g' "$f"
done < <(git grep -I -l -i -E 'srv[-_]tune' -- .)
mv docs/srv-tune.1 docs/temper.1
mv completion/srv-tune.bash completion/temper.bash
echo "rename pass done"
```

- [ ] **Step 3: Run it**

Run: `REPO_ROOT=<repo-path> bash %TEMP%/opencode/rename-temper.sh` (the script `cd`s to `$REPO_ROOT`; it can run from anywhere)
Expected: `rename pass done`; `git status --short` shows ~94 `M` files, ` D` for the two old names, and `??` for `docs/temper.1` + `completion/temper.bash` (plain `mv`, so git sees delete+untracked — staged with the rest in step 6).

- [ ] **Step 4: Sanity greps** (interim state — CHANGELOG/spec/plan are the only allowed hits; renamed docs are untracked so `--untracked` is required)

```bash
git grep --untracked -n -i -E 'srv[-_]tune' -- . | grep -vE 'CHANGELOG.md|docs/superpowers/(specs|plans)/2026-10-19'
```
Expected: no output (CHANGELOG's 3 historical lines and the two 2026-10-19 docs are the only allowed hits). Then compounding check:

```bash
git grep --untracked -n -E 'TEMPER_TEMPER|temper_tune|temper-temper' -- . || echo "no compounding artifacts"
```
Expected: `no compounding artifacts`. Also spot-check `lib/common.sh:13` → `TEMPER_NAME="temper"` and `docs/temper.1:1` → `.TH TEMPER 1 ... "temper 0.4.0" ...`.

- [ ] **Step 5: Full local verification on the working tree**

Run: `bash %TEMP%/opencode/run-bats.sh tests/` (the helper sets the py3/bats shim PATH and `cd`s to the repo), then `bash tests/hygiene.sh` and `bash tests/pre-publish.sh`.
Expected: all bats tests pass (0 failures), `hygiene: clean`, `pre-publish: clean`.
(`test_docs.bats` passes because both the man page and its pin say `temper $(cat VERSION)` = `temper 0.4.0` at this stage.)

- [ ] **Step 6: Commit C2**

```bash
git status --short   # expect: only sed-touched files; CHANGELOG.md and the two 2026-10-19 docs absent
git add -A
git status --short | grep -E 'CHANGELOG|2026-10-19' || echo "exclusions clean"
git commit -m "chore(rename): srv-tune -> temper across code, tests, packaging, docs"
```

### Task 2: Identity records (C3)

**Files:** `VERSION`, `docs/temper.1`, `install.sh`, `CHANGELOG.md`, `README.md`, `README.fa.md`, `docs/VERIFICATION-DEBT.md`.
**Interfaces — Consumes:** renamed tree from Task 1. **Produces:** final allowlist state (guard-clean), `VERSION=0.5.0`.

- [ ] **Step 1: `VERSION`** → exactly `0.5.0` (one line).
- [ ] **Step 2: `docs/temper.1`** → `.TH TEMPER 1 "2026-10-19" "temper 0.5.0" "System administration"` (version string only; `test_docs.bats` pins `temper $(cat VERSION)`).
- [ ] **Step 3: `install.sh`** line 8 pinned example — `#   ./install.sh --tag v0.4.0 --sha256 <sum> [--prefix ...]  # pinned release` → `v0.5.0` (example only; the real asset exists after the v0.5.0 release).
- [ ] **Step 4: `CHANGELOG.md`** → insert above `## v0.4.0 (2026-10-19)`:

```md
## Unreleased

- Renamed the project to **Temper**: command, env vars (`TEMPER_*`), state dir
  (`/var/lib/temper`), sshd drop-ins (`00-temper*.conf`), release assets, and the
  GitHub repository. No compatibility alias: on hosts that ran the old name, the
  old drop-ins (`00-srv-tune*.conf`) and the old state tree (`/var/lib/srv-tune`)
  are orphans — remove them by hand.
```

- [ ] **Step 5: READMEs** — insert the line as the first paragraph after the closing `</div>` of the header block (both files; keep the existing blank-line spacing):

`README.md`:
```md
**Temper** (formerly **srv-tune**): the rename ships with v0.5.0 and has no migration —
on hosts that ran the old name, remove the old drop-ins (`00-srv-tune*.conf`) and the
old state tree (`/var/lib/srv-tune`) by hand.
```

`README.fa.md` (Persian, same meaning):
```md
**Temper** (پیش‌تر **srv-tune**): تغییر نام از v0.5.0 اعمال شد و مهاجرت خودکار ندارد —
روی سرورهایی که نام قبلی نصب بوده، drop-inهای قدیمی (`00-srv-tune*.conf`) و مسیر state
قدیمی (`/var/lib/srv-tune`) را دستی حذف کنید.
```

- [ ] **Step 6: Guard grep — the success criterion** (exact allowlist: CHANGELOG historical 3 lines + the new Unreleased bullet, README×2 formerly lines, the DEBT row, the pre-publish historical-email exception)

```bash
git grep -l -i -E 'srv[-_]tune' -- . | sort   # must be exactly 7 files
git grep -c -i -E 'srv[-_]tune' -- CHANGELOG.md   # expect 5 (3 historical lines + 2 in the new bullet)
git grep -n -i -E 'srv[-_]tune' -- CHANGELOG.md | head -3   # the 3 historical hits (originally lines 7/17/43) unchanged, still srv-tune
```
Expected file list: `CHANGELOG.md`, `README.md`, `README.fa.md`, `docs/VERIFICATION-DEBT.md`, `tests/pre-publish.sh` (historical email allowlist, 2 lines), `docs/superpowers/plans/2026-10-19-rename-temper.md`, `docs/superpowers/specs/2026-10-19-rename-temper-design.md` — nothing else. Every hit inside the first four files is one of the enumerated new lines plus CHANGELOG's 3 historical lines.

- [ ] **Step 7: `docs/VERIFICATION-DEBT.md`** — append a dated status entry directly after the existing `[x] Status 2026-10-18` entry (still inside the `## Round 2 data hardening (open)` list, before `## Manual scenario tracker`):

```md
- [x] Status 2026-10-19 (rename to Temper): mechanical rename PR — case-sensitive
  mapping, history-preserving allowlist, guard grep limited to the enumerated
  exceptions; full CI green on the PR. Post-merge: repository renamed, 301 redirect +
  new raw URL checked, dry-run release artifact prefix checked (evidence: PR thread).
```

- [ ] **Step 8: Re-run full local verification** (same commands as Task 1 step 5).
Expected: all green (`temper 0.5.0` everywhere consistent).

- [ ] **Step 9: Commit C3**

```bash
git add VERSION docs/temper.1 install.sh CHANGELOG.md README.md README.fa.md docs/VERIFICATION-DEBT.md
git commit -m "chore(release): bump VERSION to 0.5.0, records for the Temper rename"
```

### Task 3: PR, CI, merge

- [ ] **Step 1: Final guard + push**

```bash
git grep -n -i -E 'srv[-_]tune' -- . | grep -vE 'CHANGELOG.md|README.md|README.fa.md|docs/VERIFICATION-DEBT.md|tests/pre-publish.sh|docs/superpowers/(specs|plans)/2026-10-19' || echo "guard: clean"
git push -u origin v0.5/rename-temper
```

- [ ] **Step 2: PR** — title `chore(rename): srv-tune -> temper (v0.5.0)`; body: mapping summary, guard-grep output, exception list, and "post-merge steps (repo rename, redirect, dry-run) will be recorded as a comment here".
- [ ] **Step 3: Checks** — `gh pr checks <N> --watch` → all pass (5 required + scan-matrix).

- [ ] **Step 4: Merge + master CI**

```bash
gh pr merge <N> --merge --delete-branch
git checkout master && git pull --ff-only origin master
bash %TEMP%/opencode/master-watch.sh     # master CI green + pre-publish clean
```

### Task 4: Repo rename + live verification + evidence comment

> After this task the remote is `KanekiDevPro/temper`; update any operator helper scripts under `%TEMP%/opencode` that hardcode `KanekiDevPro/srv-tune` (one `sed` pass).

- [ ] **Step 1: Rename via API** (deterministic, non-interactive):

```bash
gh api -X PATCH repos/KanekiDevPro/srv-tune -f name=temper
git remote set-url origin https://github.com/KanekiDevPro/temper.git
git fetch origin && git status
```

- [ ] **Step 2: Verify name + settings survive**

```bash
gh repo view KanekiDevPro/temper --json name,description --jq '.name'
gh api repos/KanekiDevPro/temper/branches/master/protection --jq '[.required_status_checks.contexts, .enforce_admins.enabled]'
gh api repos/KanekiDevPro/temper/private-vulnerability-reporting
```
Expected: `temper`; the 5 contexts + `true`; `{"enabled":true}`. If the description/topics mention the old name, fix with `gh repo edit`.

- [ ] **Step 3: Redirect + URL checks**

```bash
curl -sI https://github.com/KanekiDevPro/srv-tune | grep -iE '^HTTP|^location'
curl -s -o /dev/null -w '%{http_code}\n' https://raw.githubusercontent.com/KanekiDevPro/temper/master/README.md
curl -s -o /dev/null -w '%{http_code}\n' https://github.com/KanekiDevPro/temper/actions/workflows/ci.yml/badge.svg
```
Expected: `301` + `location: https://github.com/KanekiDevPro/temper`; `200`; `200`.

- [ ] **Step 4: In-tree URL guard + dry-run release smoke test**

```bash
git grep -n 'KanekiDevPro/srv-tune' -- . ':!docs/superpowers' || echo "no stale repo URLs"   # spec/plan quote the old URL by design
gh workflow run release.yml -f dry-run=true
gh run list --workflow release.yml -L 3
# then, with the new run id:
gh run watch <id> --exit-status
gh run download <id> --dir "%TEMP%/opencode/reldry" && ls "%TEMP%/opencode/reldry"
```
Expected: no stale URLs outside `docs/superpowers` (`lib/update.sh` default repo and `schema/scanner-v1.json` `$id` were renamed in C2); run green; artifact dir contains `temper-dry-run-<sha8>.tar.gz` + `sha256sums.txt`.

- [ ] **Step 5: Evidence comment on the merged PR**

```bash
gh pr comment <N> --repo KanekiDevPro/temper --body "Post-merge verification: 301 redirect OK; raw URL 200; badge 200; repo name temper; protection contexts intact; dry-run artifact temper-dry-run-*.tar.gz."
```

## Out of scope (explicitly deferred)

- Release-prep PR (dates the `## Unreleased` heading, review, then tag `v0.5.0` + publish) — explicit user instruction required, same flow as v0.4.0.
- Renaming the local checkout folder `Default Project/srv-tune` → `temper` (optional; breaks operator helper paths until they are updated in one pass).
- A permanent grep-guard test — rejected in the spec (brittle against enumerated history).
- Re-publishing old releases under new asset names — history stays as shipped.
