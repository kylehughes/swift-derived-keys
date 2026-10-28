# Size-facade release sample

This sample records one run of the [benchmark suite](README.md#size-facade-workload-and-cases) on 2026-10-28 at 20:24 UTC. Each case ran once in a separate process. These are measurements of synthetic byte-mixing calculations through `SizeCache`, not UIKit fitting measurements or a performance guarantee.

```sh
BENCHMARK_SCRATCH_PATH=.build/size-benchmark-build \
BENCHMARK_OUTPUT_DIR=/tmp/derivedkeys-size-comparison-20261028 \
Benchmarks/run.sh
```

| Setting | Value |
| --- | --- |
| Hardware | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB memory |
| Host | macOS 27.2 (26B123), Darwin 27.2.0, arm64 |
| Compiler | Apple Swift 6.4, `swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`; driver 1.168.6 |
| Compiler target | `arm64-apple-macosx27.2.0` |
| Configuration | SwiftPM release; Swift 6 language mode; tools version 6.4; package macOS 13 minimum |
| Workload | 1,000 measured operations; 4,096-byte payload per child; capacity 128 per cache |
| Proposal | 320 by 240 points, forwarded unchanged to both children |
| Calculation | Each child performs four passes of wrapping integer mixing; the parent combines both returned sizes and spacing |

Both children reference the same immutable byte-array buffer and select different integer variants. The parent selects spacing and orientation, then includes both mapped child descriptions. Graph construction and warmup occur before timing. Input assembly, dependency capture, key hashing, and cache work are included in the loops where used. Snapshot-only hashing and the result validation pass occur after timing.

## Timings and counts

The times are means within each named loop, in microseconds per operation. Counts and entries are listed in parent / left child / right child order.

| Case | µs/operation | Measured calculations | Warmup calculations | Final entries |
| --- | ---: | ---: | ---: | ---: |
| `size-snapshot` | 3.919 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| `size-warm-parent` | 2,627.813 | 0 / 0 / 0 | 1 / 1 / 1 | 1 / 1 / 1 |
| `size-parent-miss` | 6,837.689 | 1,000 / 0 / 0 | 0 / 1 / 1 | 128 / 1 / 1 |
| `size-cold` | 17,861.035 | 1,000 / 1,000 / 1,000 | 0 / 0 / 0 | 128 / 128 / 128 |
| `size-direct` | 47.427 | 1,000 / 1,000 / 1,000 | 0 / 0 / 0 | 0 / 0 / 0 |

Runtime checks accepted every expected calculation count. Each result-producing case also matched direct calculation over its own inputs. The cold and direct cases used identical changing child variants and both produced checksum `23092887143`. Parent misses changed only spacing; child variants and effective proposals stayed fixed, so every child request hit its warmed entry.

The warmed parent avoided all measurement calls but took longer than direct calculation in this sample. Capturing a snapshot alone was much cheaper than the warmed lookup. The lookup additionally hashes and compares complete payload-valued dependency snapshots, and the cold path also inserts and evicts across three caches. These rows do not isolate a precise cost for hashing, equality, type erasure, or LRU bookkeeping. They show that this cache and dependency representation did not pay off for this particular calculation. A more expensive measurement or a smaller stable projection can produce a different tradeoff; application profiling is needed to choose one.

The parent-miss and cold cases used bounded capacity 128 throughout. They evicted after filling; neither used capacity equal to the 1,000 iterations. For a run without those evictions, set capacity at least equal to iterations and retain that distinction when comparing results.

## Memory and measurement limits

| Case | Whole-process high-water RSS, bytes | Stored `CGSize` result bytes |
| --- | ---: | ---: |
| `size-snapshot` | 6,373,376 | 0 |
| `size-warm-parent` | 6,324,224 | 48 |
| `size-parent-miss` | 6,651,904 | 2,080 |
| `size-cold` | 6,864,896 | 6,144 |
| `size-direct` | 6,242,304 | 0 |

Stored result bytes equal final entry counts multiplied by the 16-byte `CGSize` stride on this machine. They exclude all keys, closures, dictionaries, LRU storage, spare capacity, and allocator overhead. Total retained key bytes and allocation counts were not measured. The input and selected snapshots share one 4,096-byte payload buffer, so multiplying payload size by entry count would not describe unique retained bytes.

RSS comes from `/usr/bin/time -l` and covers the entire process, including graph setup, warmup, snapshot-checksum hashing, direct result validation, and JSON output. The direct case constructs the same graph outside timing but does not use its result storage. RSS cannot establish per-phase memory use or memory owned exclusively by cache entries.

There was one sample per case with no controlled system-load or power experiment, confidence interval, or timer-overhead subtraction. The full runner also executed the existing generic cases successfully. Their historical [recorded sample](Results.md) remains unchanged and was captured under a different host environment.

## Source fingerprints and raw observations

The runner retained metadata, JSON Lines measurements, and per-case resource reports in `/tmp/derivedkeys-size-comparison-20261028`. The principal SHA-256 fingerprints recorded with this run were:

```text
1a206f08593e69d39f87f63fa62d6059318c81130f2ad7885832e5cf4015e25e  Benchmarks/run.sh
a31ea079bd6ed3128830f7cf7ff6a48bf68c02b94348be66da4474e62adc674f  Sources/DerivedKeysBenchmarks/Benchmark.swift
99a7ef75f018acb83b8772789064ef315ef3b36885b30431e32c00cc01618280  Sources/DerivedKeysBenchmarks/SizeBenchmark.swift
bd7efbf5b42084014ec6e70fa80e696402b41f86c682f0f71029a4c3f0ca0ab4  Sources/DerivedKeys/DependencySnapshot.swift
b6c32783507022fd6b8ac0823e67a2cac4006c6490f198593beee4f4710f409b  Sources/DerivedKeysUI/SizeCache.swift
69099e2298fdf3ac38d21a7767da0b1db81fd3ea99402d945da6d0aa366a074e  Sources/DerivedKeysUI/SizeDependencies.swift
```
