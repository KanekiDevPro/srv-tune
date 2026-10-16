#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Scan JSON schema: contract file + stdlib-only validator.
# shellcheck shell=bash

load bats_helper

@test "schema file exists and is valid JSON" {
  [ -f "$SRV_TUNE_ROOT/schema/scanner-v1.json" ]
  if command -v python3 >/dev/null 2>&1; then
    run python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SRV_TUNE_ROOT/schema/scanner-v1.json"
    [ "$status" -eq 0 ]
  elif command -v node >/dev/null 2>&1; then
    run node -e 'JSON.parse(require("fs").readFileSync(process.argv[1]))' "$SRV_TUNE_ROOT/schema/scanner-v1.json"
    [ "$status" -eq 0 ]
  else
    skip "no JSON parser on this host"
  fi
}

@test "a real scan output validates against the schema" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 missing on this host"
  fi
  out="$SRV_TUNE_TMP/scan.json"
  SRV_TUNE_JSON_OUT="$out" bash "$SRV_TUNE_ROOT/scanner/scan.sh" >/dev/null
  run python3 "$SRV_TUNE_ROOT/scanner/validate.py" "$out"
  [ "$status" -eq 0 ]
}

@test "validator rejects missing keys, bad score, bad profile" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 missing on this host"
  fi
  printf '{"SCORE":"101","PROFILE":"nope"}' >"$SRV_TUNE_TMP/bad.json"
  run python3 "$SRV_TUNE_ROOT/scanner/validate.py" "$SRV_TUNE_TMP/bad.json"
  [ "$status" -ne 0 ]
  printf '{"SCORE":"5"}' >"$SRV_TUNE_TMP/bad2.json"
  run python3 "$SRV_TUNE_ROOT/scanner/validate.py" "$SRV_TUNE_TMP/bad2.json"
  [ "$status" -ne 0 ]
}

@test "schema profile enum matches profiles on disk" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 missing on this host"
  fi
  run bash -c 'ls "$1"/profiles/*.conf | xargs -n1 basename | sed "s/.conf//" | sort' bash "$SRV_TUNE_ROOT"
  profiles="$output"
  run python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["properties"]["PROFILE"]["enum"])))' "$SRV_TUNE_ROOT/schema/scanner-v1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$profiles" ]
}
