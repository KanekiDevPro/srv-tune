#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# scan --diff: flat-JSON baseline parsing, drift report, exit codes.
# shellcheck shell=bash

load bats_helper

@test "diff: parses the flat scanner JSON into key/value pairs" {
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/scanner/diff.sh"
  printf '{"A":"1","B":"x y","C":"a,b","D":"https://e:8/f"}\n' >"$TEMPER_TMP/base.json"
  run scan_diff_parse_json "$TEMPER_TMP/base.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"A"$'\t'"1"* ]]
  [[ "$output" == *"B"$'\t'"x y"* ]]
  [[ "$output" == *"C"$'\t'"a,b"* ]]
  [[ "$output" == *"D"$'\t'"https://e:8/f"* ]]
}

@test "diff: reports changed, added and removed keys plus deltas" {
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/scanner/diff.sh"
  printf '{"OS_ID":"ubuntu","KEEP":"same","GONE":"old","CHANGE":"old","SCORE":"70","PROFILE":"web"}\n' >"$TEMPER_TMP/base.json"
  printf 'OS_ID=ubuntu\nKEEP=same\nCHANGE=new\nNEW=v\n' >"$TEMPER_TMP/cur.env"
  run scan_diff_run "$TEMPER_TMP/base.json" "$TEMPER_TMP/cur.env" 78 generic
  [ "$status" -eq 0 ]
  [[ "$output" == *"score:   70 -> 78"* ]]
  [[ "$output" == *"profile: web -> generic"* ]]
  [[ "$output" == *"changed CHANGE: old -> new"* ]]
  [[ "$output" == *"added   NEW: v"* ]]
  [[ "$output" == *"removed GONE: old"* ]]
  [[ "$output" == *"1 changed, 1 added, 1 removed (4 keys)"* ]]
}

@test "diff: identical scan reports no changes" {
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/scanner/diff.sh"
  printf '{"OS_ID":"ubuntu","KEEP":"same","SCORE":"70","PROFILE":"web"}\n' >"$TEMPER_TMP/base.json"
  printf 'OS_ID=ubuntu\nKEEP=same\n' >"$TEMPER_TMP/cur.env"
  run scan_diff_run "$TEMPER_TMP/base.json" "$TEMPER_TMP/cur.env" 70 web
  [ "$status" -eq 0 ]
  [[ "$output" == *"score:   70 (unchanged)"* ]]
  [[ "$output" == *"profile: web (unchanged)"* ]]
  [[ "$output" == *"no changes (2 keys)"* ]]
}

@test "diff: missing baseline exits 2" {
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/scanner/diff.sh"
  printf 'OS_ID=ubuntu\n' >"$TEMPER_TMP/cur.env"
  run scan_diff_run "$TEMPER_TMP/nope.json" "$TEMPER_TMP/cur.env" 1 generic
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline not found"* ]]
}

@test "diff: non-flat baseline exits 2" {
  # shellcheck disable=SC1091
  source "$TEMPER_ROOT/scanner/diff.sh"
  printf '{"nested":{"a":1}}\n' >"$TEMPER_TMP/base.json"
  printf 'OS_ID=ubuntu\n' >"$TEMPER_TMP/cur.env"
  run scan_diff_run "$TEMPER_TMP/base.json" "$TEMPER_TMP/cur.env" 1 generic
  [ "$status" -eq 2 ]
  [[ "$output" == *"no KEY/VALUE pairs"* ]]
}

@test "optimizer scan --diff end-to-end" {
  run bash "$TEMPER_ROOT/optimizer.sh" scan --json "$TEMPER_TMP/base.json"
  [ "$status" -eq 0 ]
  run bash "$TEMPER_ROOT/optimizer.sh" scan --diff "$TEMPER_TMP/base.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scan diff:"* ]]
  [[ "$output" == *"score:"* ]]
  [[ "$output" == *"profile:"* ]]
}

@test "optimizer scan --diff without a file exits 2" {
  run bash "$TEMPER_ROOT/optimizer.sh" scan --diff
  [ "$status" -eq 2 ]
  [[ "$output" == *"--diff needs"* ]]
}
