#!/usr/bin/env bash
# Pre-public checklist. FAILS on: secrets in tree/history, non-allowlisted
# author emails, private paths/hostnames, missing license identifiers.
# Prints (but never applies) the branch-protection suggestion.
# shellcheck shell=bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

say() {
  printf '%s\n' "$*"
}

# 1. Secrets in the working tree (filenames + content).
if git ls-files | grep -Ei '(\.env$|\.pem$|\.key$|id_rsa|credentials|secrets\.json)' >/dev/null; then
  say 'FAIL: secret-like filenames tracked'
  fail=1
fi
if git grep -n -Ei 'ghp_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY' -- . >/dev/null; then
  say 'FAIL: secret-like content in tree'
  fail=1
fi

# 2. Secrets ever in history.
if git log --all -p -S 'BEGIN RSA PRIVATE KEY' --format='%h' | grep -q .; then
  say 'FAIL: private key material in history'
  fail=1
fi
if git log --all -p -S 'BEGIN OPENSSH PRIVATE KEY' --format='%h' | grep -q .; then
  say 'FAIL: private key material in history'
  fail=1
fi

# 3. Author emails: only project, noreply, or GitHub's own merge identity
# (noreply@github.com signs GitHub-created merges; never rewrite those).
bad="$(git log --format='%ae %ce' | tr ' ' '\n' | sort -u | grep -Ev '^(srv-tune@local|[^@]+@users\.noreply\.github\.com|noreply@github\.com)$' || true)"
if [[ -n "$bad" ]]; then
  say "FAIL: non-allowlisted emails in history: $bad"
  fail=1
fi

# 4. Private names/paths accidentally committed. Test fixtures only ever
# use TEST-NET addresses (192.0.2.x, 198.51.100.x, 203.0.113.x) and
# variable-prefixed paths ($TMP/.../home/...), which are excluded.
if git grep -n -E 'AngelOfDeath|/home/AngelOfDeath' -- . >/dev/null; then
  say 'FAIL: private name/path in tree (see above)'
  git grep -n -E 'AngelOfDeath|/home/AngelOfDeath' -- . || true
  fail=1
fi
if git grep -n -E '(192\.168\.|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.)' -- lib modules scanner bench tests optimizer.sh install.sh 2>/dev/null | grep -Ev '192\.0\.2\.|198\.51\.100\.|203\.0\.113\.' >/dev/null; then
  say 'FAIL: possible private IP in code/tests'
  fail=1
fi

# 5. License identifiers on every script.
missing=0
while IFS= read -r f; do
  case "$f" in
  *.sh | *.bash | *.bats) ;;
  *) continue ;;
  esac
  if ! grep -q 'SPDX-License-Identifier: MIT' "$f"; then
    say "FAIL: no license identifier: $f"
    missing=1
  fi
done < <(git ls-files)
if [[ "$missing" == "1" ]]; then fail=1; fi

# 6. Mirror data review gate: every entry in data/*.list carries
# verified=<status>. While ANY entry is verified=pending the tree must NOT
# be published. Only the maintainer flips entries to verified after manual
# review of owner/docs; automation must NEVER do it.
pending="$(git grep -n 'verified=pending' -- data/ 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [[ -n "$pending" ]]; then
  say 'FAIL: mirror data has verified=pending entries (manual review required):'
  say "$pending"
  fail=1
fi

# 7. Branch protection suggestion (report only, never applied here).
say 'SUGGEST: protect the default branch (require PR + green CI, no force-push to main):'
say '  gh api repos/{owner}/{repo}/branches/{main}/protection -X PUT -F required_status_checks[strict]=true -F enforce_admins=true -F required_pull_request_reviews=null -F restrictions=null'

if [[ "$fail" == "0" ]]; then
  say 'pre-publish: clean'
fi
exit "$fail"
