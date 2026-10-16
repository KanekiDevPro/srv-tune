#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Hygiene gate (mirrors CI): fails on CRLF bytes and missing exec bits.
# Executable allowlist: directly-executed scripts. Sourced libs stay 644.
# shellcheck shell=bash
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# 1. No CR bytes in tracked text files.
while IFS= read -r f; do
  case "$f" in
  *.gif | *.png) continue ;;
  esac
  if grep -q $'\r' "$f" 2>/dev/null; then
    printf 'CRLF-FAIL: %s\n' "$f"
    fail=1
  fi
done < <(git ls-files)

# 2. Forbidden destructive patterns in shipped code (tests + docs exempt:
# they must contain these strings to assert refusal).
forbidden() {
  # forbidden <ere> <label> [exempt_ere]
  local pat="$1" label="$2" exempt="${3:-}"
  local hits
  hits="$(git grep -n -E -- "$pat" -- 'lib' 'modules' 'scanner' 'optimizer.sh' 2>/dev/null || true)"
  if [[ -n "$exempt" ]]; then
    hits="$(printf '%s\n' "$hits" | grep -Ev -- "$exempt" || true)"
  fi
  if [[ -n "$hits" ]]; then
    printf 'FORBIDDEN %s:\n%s\n' "$label" "$hits"
    fail=1
  fi
}
forbidden 'flush ruleset' 'nft flush'
forbidden 'iptables -[FX]' 'iptables flush'
forbidden 'ufw --force reset' 'ufw reset'
forbidden 'rm -rf /(\*|$)' 'rm-rf root'
forbidden 'rm -rf \$' 'rm-rf unquoted var'
forbidden 'restart ssh\.service|restart sshd|restart ssh( |$)' 'ssh-service restart (reload only)'
forbidden 'ssh/sshd_config([^._/d]|$)' 'main sshd_config edit (drop-in only)'
# The mirror module only ever GREPS for these to refuse them.
forbidden 'trusted=yes|Trusted: yes|allow-insecure|Allow-Insecure' 'weakened apt trust' 'weakens trust|refusing|refuse such|must not|never|grep -Eq'
# Registry mirrors: HTTPS only, no insecure-registry/trusted-host anywhere.
forbidden 'insecure-registries|trusted-host' 'insecure registry options'
for f in modules/pip_mirror.sh modules/npm_mirror.sh modules/docker_mirror.sh data/mirrors-pip.list data/mirrors-npm.list data/mirrors-docker.list; do
  if git grep -n -E -- 'http://' -- "$f" 2>/dev/null | grep -Ev 'HTTPS only|plain http|http://URLs|http:// URL' >/dev/null; then
    printf 'FORBIDDEN plain-http in registry file:\n'
    git grep -n -E -- 'http://' -- "$f" 2>/dev/null | grep -Ev 'HTTPS only|plain http|http://URLs|http:// URL' || true
    fail=1
  fi
done
# Registry modules touch system files only: no home dirs, no lockfiles.
if git grep -n -E -- 'HOME|~/|package-lock|lockfile' -- modules/pip_mirror.sh modules/npm_mirror.sh modules/docker_mirror.sh 2>/dev/null >/dev/null; then
  printf 'FORBIDDEN home-dir/lockfile reference in registry modules:\n'
  git grep -n -E -- 'HOME|~/|package-lock|lockfile' -- modules/pip_mirror.sh modules/npm_mirror.sh modules/docker_mirror.sh 2>/dev/null || true
  fail=1
fi
# NOTE: `systemctl restart ssh.socket` is INTENTIONALLY allowed: socket units
# cannot reload ListenStream bindings; ssh.service/sshd must always reload
# (covered by the ssh-service-restart rule above).

# 3. Exec bit present on every directly-executed script.
while IFS= read -r f; do
  mode="$(git ls-files -s "$f" | awk '{print $1}')"
  if [[ "$mode" != "100755" ]]; then
    printf 'EXEC-FAIL: %s has mode %s\n' "$f" "$mode"
    fail=1
  fi
done < <(git ls-files | grep -E '^(optimizer\.sh|scanner/scan\.sh|tests/.*\.sh|tests/vm/.*\.sh)$')

# 4. Workflow YAML must parse (a broken workflow fails the whole run with
# no logs). Skipped only when python3/yaml is unavailable.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  if ! python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/ci.yml"))' 2>/dev/null; then
    printf 'YAML-FAIL: .github/workflows/ci.yml does not parse\n'
    fail=1
  fi
else
  printf 'warn: python3/yaml missing, workflow parse check skipped\n' >&2
fi

if [[ "$fail" == "0" ]]; then
  printf 'hygiene: clean\n'
fi
exit "$fail"
