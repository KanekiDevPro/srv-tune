#!/usr/bin/env bats
# benchmark: installed-tools only, skips recorded, compare renders 3 formats.
# shellcheck shell=bash

load bats_helper

_setup_bench() {
  mkdir -p "$SRV_TUNE_TMP/stubbin"
  cat >"$SRV_TUNE_TMP/stubbin/ping" <<'EOF'
#!/usr/bin/env bash
printf 'rtt min/avg/max/mdev = 1.0/11.5/20.0/5.0 ms\n'
EOF
  cat >"$SRV_TUNE_TMP/stubbin/dig" <<'EOF'
#!/usr/bin/env bash
printf ';; Query time: 7 msec\n'
EOF
  cat >"$SRV_TUNE_TMP/stubbin/curl" <<'EOF'
#!/usr/bin/env bash
printf '0.042'
EOF
  cat >"$SRV_TUNE_TMP/stubbin/sysbench" <<'EOF'
#!/usr/bin/env bash
printf 'events per second: 1234.56\n'
EOF
  cat >"$SRV_TUNE_TMP/stubbin/fio" <<'EOF'
#!/usr/bin/env bash
printf '{"jobs": [{"read": {"iops": 9876.0}}]}\n'
EOF
  cat >"$SRV_TUNE_TMP/stubbin/iperf3" <<'EOF'
#!/usr/bin/env bash
printf '[  5] 0.00-5.00 sec 100 MBytes 168 Mbits/sec receiver\n'
EOF
  chmod +x "$SRV_TUNE_TMP/stubbin/"*
  export PATH="$SRV_TUNE_TMP/stubbin:$PATH"
}

@test "benchmark captures stubbed tools into JSON" {
  _setup_bench
  run bash "$SRV_TUNE_ROOT/bench/bench.sh" "$SRV_TUNE_TMP/b1"
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_TMP/b1/bench.json" ]
  grep -q '"latency_ms": 11.5' "$SRV_TUNE_TMP/b1/bench.json"
  grep -q '"dns_ms": 7' "$SRV_TUNE_TMP/b1/bench.json"
  grep -q '"sysbench_eps": 1234.56' "$SRV_TUNE_TMP/b1/bench.json"
}

@test "benchmark records skips for missing tools, no iperf without server" {
  _setup_bench
  export SRV_TUNE_BENCH_FORCE_MISSING="ping dig curl sysbench fio iperf3"
  run bash "$SRV_TUNE_ROOT/bench/bench.sh" "$SRV_TUNE_TMP/b2"
  unset SRV_TUNE_BENCH_FORCE_MISSING
  [ "$status" -eq 0 ]
  grep -q '"latency_ms": null' "$SRV_TUNE_TMP/b2/bench.json"
  grep -q 'needs --iperf-server' "$SRV_TUNE_TMP/b2/bench.json"
}

@test "benchmark runs iperf3 only with an explicit server" {
  _setup_bench
  run bash "$SRV_TUNE_ROOT/bench/bench.sh" "$SRV_TUNE_TMP/b3" --iperf-server=example.com
  [ "$status" -eq 0 ]
  grep -q '"iperf_mbps": 168' "$SRV_TUNE_TMP/b3/bench.json"
}

@test "compare renders markdown, json and html" {
  printf '{"latency_ms": 10, "dns_ms": 5}\n' >"$SRV_TUNE_TMP/before.json"
  printf '{"latency_ms": 20, "dns_ms": 5}\n' >"$SRV_TUNE_TMP/after.json"
  run bash "$SRV_TUNE_ROOT/bench/compare.sh" "$SRV_TUNE_TMP/before.json" "$SRV_TUNE_TMP/after.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| latency_ms | 10 | 20 |"* ]]
  run bash "$SRV_TUNE_ROOT/bench/compare.sh" "$SRV_TUNE_TMP/before.json" "$SRV_TUNE_TMP/after.json" --format=json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"before"'* ]]
  run bash "$SRV_TUNE_ROOT/bench/compare.sh" "$SRV_TUNE_TMP/before.json" "$SRV_TUNE_TMP/after.json" --format=html
  [ "$status" -eq 0 ]
  [[ "$output" == *"<table>"* ]]
}

@test "optimizer benchmark captures and compares end to end" {
  _setup_bench
  run bash "$SRV_TUNE_ROOT/optimizer.sh" benchmark --out "$SRV_TUNE_TMP/b4"
  [ "$status" -eq 0 ]
  [ -f "$SRV_TUNE_TMP/b4/bench.json" ]
  run bash "$SRV_TUNE_ROOT/optimizer.sh" benchmark --compare "$SRV_TUNE_TMP/b4/bench.json" "$SRV_TUNE_TMP/b4/bench.json" --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *"metric"* ]]
}
