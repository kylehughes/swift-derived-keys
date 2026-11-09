#!/bin/bash
set -euo pipefail

benchmark_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$benchmark_root"
benchmark_output=${BENCHMARK_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/derivedkeys-benchmarks.XXXXXX")}
mkdir -p "$benchmark_output"
benchmark_output=$(cd "$benchmark_output" && pwd)

benchmark_build_options=(-c release)
if [[ -n "${BENCHMARK_SCRATCH_PATH:-}" ]]; then
    benchmark_build_options+=(--scratch-path "$BENCHMARK_SCRATCH_PATH")
fi
swift build "${benchmark_build_options[@]}" --product DerivedKeysBenchmarks
benchmark_bin_dir=$(swift build "${benchmark_build_options[@]}" --show-bin-path)
benchmark_binary="$benchmark_bin_dir/DerivedKeysBenchmarks"

{
    printf 'UTC date: '
    date -u '+%Y-%m-%dT%H:%M:%SZ'
    printf 'Compiler:\n'
    swift --version 2>&1
    printf 'SwiftPM configuration: release; Swift language mode: 6; tools version: 6.4\n'
    printf 'OS:\n'
    sw_vers
    uname -smr
    printf 'Hardware:\n'
    for benchmark_property in hw.model machdep.cpu.brand_string hw.memsize hw.ncpu; do
        printf '%s: ' "$benchmark_property"
        sysctl -n "$benchmark_property" 2>/dev/null || printf 'unknown\n'
    done
    printf 'Arguments:'
    if (( $# > 0 )); then
        printf ' %q' "$@"
    else
        printf ' (defaults)'
    fi
    printf '\nSource SHA-256 digests:\n'
    shasum -a 256 Package.swift Benchmarks/run.sh Sources/DerivedKeys/*.swift \
        Sources/DerivedKeysUI/*.swift Sources/DerivedKeysBenchmarks/*.swift
    printf 'Allocation counts: unknown; no allocation profiler attached.\n'
    printf 'RSS: /usr/bin/time -l per case; whole-process high-water mark.\n'
} > "$benchmark_output/metadata.txt"

printf 'Benchmark output: %s\n' "$benchmark_output"
cat "$benchmark_output/metadata.txt"
for benchmark_case in \
    typed-projection typed-hash direct cold-miss warm-hit \
    relevant-change irrelevant-change large-payload shared-source eviction \
    size-snapshot size-warm-parent size-parent-miss size-cold size-direct; do
    /usr/bin/time -l "$benchmark_binary" "$@" --case "$benchmark_case" \
        > "$benchmark_output/$benchmark_case.jsonl" \
        2> "$benchmark_output/$benchmark_case.time.txt"
    cat "$benchmark_output/$benchmark_case.jsonl"
done
