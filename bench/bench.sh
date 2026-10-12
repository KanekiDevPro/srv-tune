#!/usr/bin/env bash
# Benchmark capture: BEFORE/AFTER metrics using ONLY installed tools.
# Missing tools are recorded as skipped, never installed (unless
# --install-deps is passed explicitly). iperf3 runs ONLY with --iperf-server.
# Output: $outdir/bench.json (flat metric + note fields).
# shellcheck shell=bash
set -euo pipefail

OUTDIR="${1:-bench-out}"
IPERF_SERVER=""
INSTALL_DEPS=0
for a in "$@"; do
  case "$a" in
  --iperf-server=*) IPERF_SERVER="${a#*=}" ;;
  --install-deps) INSTALL_DEPS=1 ;;
  esac
done

mkdir -p "$OUTDIR"

if [[ "$INSTALL_DEPS" == "1" ]]; then
  # Explicit opt-in only: install the benchmark toolset via apt.
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq iputils-ping dnsutils curl iperf3 sysbench fio 2>/dev/null || true
  else
    printf 'warn: --install-deps needs apt-get; continuing with installed tools\n' >&2
  fi
fi

# bench_have <name> - 0 when usable: present on PATH and not force-missing.
bench_have() {
  local n="$1"
  case " ${SRV_TUNE_BENCH_FORCE_MISSING:-} " in
  *" $n "*) return 1 ;;
  esac
  command -v "$n" >/dev/null 2>&1
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

OUT="$OUTDIR/bench.json"
{
  printf '{\n'
  printf '"date": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"

  # latency_ms: ICMP to a public resolver (network reachability proxy).
  if bench_have ping; then
    lat="$(ping -c 4 -W 2 1.1.1.1 2>/dev/null | awk -F'[=/]' '/rtt|round-trip/{gsub(/ /, "", $6); print $6}' || true)"
    if [[ -n "$lat" ]]; then
      printf '"latency_ms": %s,\n' "$lat"
    else
      printf '"latency_ms": null,\n"latency_note": "ping produced no RTT line",\n'
    fi
  else
    printf '"latency_ms": null,\n"latency_note": "skipped (ping missing)",\n'
  fi

  # dns_ms: query time reported by dig itself.
  if bench_have dig; then
    ms="$(dig +time=3 +tries=1 example.com 2>/dev/null | grep 'Query time' | grep -o '[0-9][0-9]* msec' | awk '{print $1}' | head -n 1 || true)"
    if [[ -n "$ms" ]]; then
      printf '"dns_ms": %s,\n' "$ms"
    else
      printf '"dns_ms": null,\n"dns_note": "dig produced no answer",\n'
    fi
  else
    printf '"dns_ms": null,\n"dns_note": "skipped (dig missing)",\n'
  fi

  # mirror_s: time to fetch headers from the first configured apt URI.
  if bench_have curl; then
    uri="$(grep -rhoE 'https?://[^ ]+' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | head -n 1 || true)"
    if [[ -n "$uri" ]]; then
      printf '"mirror_uri": %s,\n' "$(json_str "$uri")"
      secs="$(curl -s -o /dev/null -w '%{time_total}' --max-time 15 "$uri" 2>/dev/null || printf '')"
      if [[ -n "$secs" ]]; then
        printf '"mirror_s": %s,\n' "$secs"
      else
        printf '"mirror_s": null,\n"mirror_note": "fetch failed",\n'
      fi
    else
      printf '"mirror_uri": null,\n"mirror_s": null,\n"mirror_note": "no apt URI found",\n'
    fi
  else
    printf '"mirror_s": null,\n"mirror_note": "skipped (curl missing)",\n'
  fi

  # iperf3: ONLY with an explicit server (never unasked network load).
  if [[ -n "$IPERF_SERVER" ]]; then
    if bench_have iperf3; then
      mbps="$(iperf3 -c "$IPERF_SERVER" -t 5 -f m 2>/dev/null | grep -o '[0-9.]* Mbits/sec' | tail -n 1 | awk '{print $1}' || true)"
      if [[ -n "$mbps" ]]; then
        printf '"iperf_mbps": %s,\n' "$mbps"
      else
        printf '"iperf_mbps": null,\n"iperf_note": "iperf3 produced no result",\n'
      fi
    else
      printf '"iperf_mbps": null,\n"iperf_note": "skipped (iperf3 missing)",\n'
    fi
  else
    printf '"iperf_mbps": null,\n"iperf_note": "skipped (needs --iperf-server=HOST)",\n'
  fi

  # sysbench cpu events/s.
  if bench_have sysbench; then
    eps="$(sysbench cpu --cpu-max-prime=2000 run 2>/dev/null | awk '/events per second:/{print $4}' || true)"
    if [[ -n "$eps" ]]; then
      printf '"sysbench_eps": %s,\n' "$eps"
    else
      printf '"sysbench_eps": null,\n"sysbench_note": "sysbench produced no result",\n'
    fi
  else
    printf '"sysbench_eps": null,\n"sysbench_note": "skipped (sysbench missing)",\n'
  fi

  # fio 4k randread IOPS in a temp dir (64MB, 10s cap).
  if bench_have fio; then
    fdir="$(mktemp -d "${TMPDIR:-/tmp}/srv-fio-XXXXXX")"
    iops="$(fio --name=t --rw=randread --bs=4k --size=64m --runtime=10 --time_based --direct=1 --directory="$fdir" --output-format=json 2>/dev/null | grep -o '"iops"[^,]*' | head -n 1 | grep -o '[0-9.]*' | head -n 1 || true)"
    rm -rf "$fdir"
    if [[ -n "$iops" ]]; then
      printf '"fio_iops": %s\n' "$iops"
    else
      printf '"fio_iops": null,\n"fio_note": "fio produced no result"\n'
    fi
  else
    printf '"fio_iops": null,\n"fio_note": "skipped (fio missing)"\n'
  fi
  printf '}\n'
} >"$OUT"
printf 'wrote %s\n' "$OUT"
