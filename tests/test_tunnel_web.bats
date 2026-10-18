#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Tunnel web panel: auth, CSRF, rate limit, token file, API shape.
# Runs against a stub CLI; no sshd, no root, loopback only.
# shellcheck shell=bash

load bats_helper

setup() {
  export TEMPER_TEST=1
  TEMPER_TMP="$(mktemp -d "$BATS_TMPDIR/srv-web-XXXXXX")"
  export TEMPER_TMP
  export TEMPER_STATE_DIR="$TEMPER_TMP/state"
  export TEMPER_LOCK_FILE="$TEMPER_TMP/lock"
  export TEMPER_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TEMPER_STATE_DIR/backups"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  command -v curl >/dev/null 2>&1 || skip "curl not installed"
  PORT=$((20000 + (RANDOM % 20000)))
  BASE="http://127.0.0.1:$PORT"
  JAR="$TEMPER_TMP/jar"
  PAGE="$TEMPER_TMP/page.html"
  TOKEN_FILE="$TEMPER_STATE_DIR/web/token"
  case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) SKIP_CLI=1 ;;
  *) SKIP_CLI=0 ;;
  esac
  export TEMPER_TEST_CALLS="$TEMPER_TMP/calls.log"
  : >"$TEMPER_TEST_CALLS"
  _write_stub
  PYTHON="$(command -v python3)"
  "$PYTHON" "$TEMPER_ROOT/web/tunnel_web.py" \
    --port "$PORT" --state-dir "$TEMPER_STATE_DIR" \
    --bin "$TEMPER_TMP/stub-temper" >"$TEMPER_TMP/web.log" 2>&1 &
  SERVER_PID=$!
  _wait_for 50 test -f "$TOKEN_FILE" || {
    cat "$TEMPER_TMP/web.log" >&2
    false
  }
  # The token file is written before the socket binds; wait for the port so
  # the first request cannot race a slow start (flake seen in CI: curl 7 on
  # the dashboard test).
  _wait_for 50 curl -s -o /dev/null "$BASE/" || {
    cat "$TEMPER_TMP/web.log" >&2
    false
  }
  TOKEN="$(cat "$TOKEN_FILE")"
}

teardown() {
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "${TEMPER_TMP:-}" 2>/dev/null || true
}

_wait_for() {
  local tries="$1" i=0
  shift
  while ! "$@" >/dev/null 2>&1; do
    i=$((i + 1))
    [[ "$i" -ge "$tries" ]] && return 1
    sleep 0.2
  done
  return 0
}

_write_stub() {
  cat >"$TEMPER_TMP/stub-temper" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TEMPER_TEST_CALLS:?}"
case "$*" in
  "tunnel status --json")
    printf '%s\n' '{"mode":"TUNNEL","port":"22","user":"tunnel","permit_open":"none","gateway_ports":false,"permit_tunnel":false,"ip_forward":false,"dropin":"/tmp/x","dropin_present":true,"sessions":0}'
    ;;
  "tunnel sessions --json") printf '%s\n' '{"sessions":[]}' ;;
  "tunnel keys list --json")
    printf '%s\n' '{"keys":[{"fp":"SHA256:abc","type":"ED25519","comment":"laptop"}]}'
    ;;
  "tunnel keys add"*) cat >/dev/null; printf 'added SHA256:abc (laptop)\n' ;;
  "tunnel keys remove"*) printf 'removed SHA256:abc\n' ;;
  *) printf 'unexpected: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$TEMPER_TMP/stub-temper"
}

_login() {
  curl -sL -c "$JAR" "$BASE/?token=$TOKEN" -o "$PAGE"
}

_csrf() {
  sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' "$PAGE" | head -n1
}

_chmod_effective() {
  local probe="$TEMPER_TMP/permprobe"
  printf 'x\n' >"$probe"
  chmod 600 "$probe" 2>/dev/null || return 1
  [[ "$(stat -c '%a' "$probe" 2>/dev/null)" == "600" ]]
}

@test "web panel self-check passes" {
  run "$PYTHON" "$TEMPER_ROOT/web/tunnel_web.py" --self-check
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-check ok"* ]]
}

@test "dashboard and API require the token cookie" {
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/"
  [ "$output" = "401" ]
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/api/status"
  [ "$output" = "401" ]
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/?token=wrong"
  [ "$output" = "401" ]
}

@test "unknown routes 404 and wrong methods 405" {
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/nope"
  [ "$output" = "404" ]
  run curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/nope"
  [ "$output" = "404" ]
  run curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/status"
  [ "$output" = "405" ]
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/api/keys/add"
  [ "$output" = "405" ]
}

@test "non-ASCII credentials are rejected, not crashed" {
  run curl -s -o /dev/null -w '%{http_code}' "$BASE/?token=%C3%A9"
  [ "$output" = "401" ]
  run curl -s -o /dev/null -w '%{http_code}' -H 'Cookie: st=é' "$BASE/"
  [ "$output" = "401" ]
  curl -s -c "$JAR" "$BASE/?token=$TOKEN" -o /dev/null
  run curl -s -b "$JAR" -H 'Content-Type: application/json' -H 'X-CSRF: é' \
    -d '{"fp":"SHA256:abc"}' -o /dev/null -w '%{http_code}' \
    "$BASE/api/keys/remove"
  [ "$output" = "403" ]
}

@test "login renders the dashboard with status, sessions, and keys" {
  [[ "${SKIP_CLI:-0}" == "1" ]] && skip "stub CLI needs POSIX exec (Linux CI covers it)"
  _login
  grep -q 'id="status"' "$PAGE"
  grep -q 'laptop' "$PAGE"
  [[ "$(grep -c 'name="csrf"' "$PAGE")" -ge 1 ]]
}

@test "mutations require the CSRF field" {
  [[ "${SKIP_CLI:-0}" == "1" ]] && skip "stub CLI needs POSIX exec (Linux CI covers it)"
  _login
  local csrf code
  code="$(curl -s -b "$JAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "key=ssh-ed25519 AAAAtest" "$BASE/api/keys/add")"
  [ "$code" = "403" ]
  run grep -q 'keys add' "$TEMPER_TEST_CALLS"
  [ "$status" -ne 0 ]
  csrf="$(_csrf)"
  [ -n "$csrf" ]
  code="$(curl -s -b "$JAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "csrf=$csrf" --data-urlencode "key=ssh-ed25519 AAAAtest" \
    --data-urlencode "comment=laptop" "$BASE/api/keys/add")"
  [ "$code" = "303" ]
  grep -q 'tunnel keys add' "$TEMPER_TEST_CALLS"
}

@test "remove validates the fingerprint and accepts JSON with X-CSRF" {
  [[ "${SKIP_CLI:-0}" == "1" ]] && skip "stub CLI needs POSIX exec (Linux CI covers it)"
  _login
  local csrf
  csrf="$(_csrf)"
  run curl -s -b "$JAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "csrf=$csrf" --data-urlencode "fp=not-a-fp" "$BASE/api/keys/remove"
  [ "$output" = "400" ]
  run grep -q 'keys remove' "$TEMPER_TEST_CALLS"
  [ "$status" -ne 0 ]
  curl -s -b "$JAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "csrf=$csrf" --data-urlencode "fp=SHA256:abc" "$BASE/api/keys/remove" >/dev/null
  grep -q -- '--fp SHA256:abc' "$TEMPER_TEST_CALLS"
  run curl -s -b "$JAR" -H 'Content-Type: application/json' -H "X-CSRF: $csrf" \
    -d '{"fp":"SHA256:def"}' "$BASE/api/keys/remove"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":true'* ]]
}

@test "status API returns JSON to an authenticated session" {
  [[ "${SKIP_CLI:-0}" == "1" ]] && skip "stub CLI needs POSIX exec (Linux CI covers it)"
  _login
  run curl -s -b "$JAR" "$BASE/api/status"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"TUNNEL"'* ]]
}

@test "token file is private" {
  _chmod_effective || skip "filesystem does not honor chmod"
  [ "$(stat -c '%a' "$TOKEN_FILE")" = "600" ]
}

@test "five wrong tokens per minute: the sixth login is rate limited" {
  local i code
  for i in 1 2 3 4 5; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/?token=wrong$i")"
    [ "$code" = "401" ]
  done
  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/?token=wrong6")"
  [ "$code" = "429" ]
}

@test "server refuses a group/world readable token file" {
  _chmod_effective || skip "filesystem does not honor chmod"
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  mkdir -p "$TEMPER_STATE_DIR/web"
  printf '0123456789abcdef0123456789abcdef\n' >"$TOKEN_FILE"
  chmod 644 "$TOKEN_FILE"
  run timeout 5 "$PYTHON" "$TEMPER_ROOT/web/tunnel_web.py" \
    --port "$PORT" --state-dir "$TEMPER_STATE_DIR" \
    --bin "$TEMPER_TMP/stub-temper"
  [ "$status" -eq 1 ]
  [[ "$output" == *"group/world readable"* ]]
  SERVER_PID=""
}
