# Release benchmark sample

This sample records one run of the [synthetic benchmark suite](Synthetic.md) on 2026-10-28 at 07:00 UTC. It is a historical measurement of this synthetic workload, with one sample per case and no statistical confidence interval.

The later [concrete-erasure comparison](Erasure-Results.md) records the representation repair; use the [synthetic methodology](Synthetic.md) to interpret or rerun these diagnostic cases. For current application-sizing measurements, start with the [native-fitting results](UIKit-Native-Fitting-Results.md); the [UIKit benchmark guide](README.md) describes the methodology and other reports; the [specialization results](Specialization-Results.md) hold the latest paired comparison.

```sh
Benchmarks/run.sh
```

| Setting | Value |
| --- | --- |
| Hardware | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB memory |
| Host | macOS 26.6.2 (25G83), Darwin 25.6.0, arm64 |
| Compiler | Apple Swift 6.4, `swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`; driver 1.168.6 |
| Compiler target | `arm64-apple-macosx26.0` |
| Configuration | SwiftPM release; Swift 6 language mode; tools version 6.4 |
| Workload | 1,000 measured operations; 4,096-byte payload; requested capacity 128 |
| Large payload | 262,144 bytes; one warmed key |
| Calculation | Four passes of wrapping integer mixing over the bytes and relevant integer format |

## Timings and computation counts

The times are means within each named loop, in microseconds per operation. Projection rows include assignment into a preallocated observation array. Hash rows use preconstructed keys. The [method definitions](Synthetic.md#workload-and-cases) explain setup and costs included in each phase.

| Case / phase | µs/operation | Measured calculations | Final cache entries |
| --- | ---: | ---: | ---: |
| Typed projection and observation | 0.141 | 0 | 0 |
| Typed key hashing | 18.319 | 0 | 0 |
| Direct calculation | 24.460 | 1,000 | 0 |
| Cold miss, no eviction | 111.750 | 1,000 | 1,000 |
| Warm typed hit | 26.566 | 0 | 64 |
| Relevant input change | 154.036 | 1,000 | 128 |
| Irrelevant input change | 25.550 | 0 | 1 |
| Large-payload warm hit | 1,614.624 | 0 | 1 |
| Shared graph: snapshot and observation | 1.950 | 0 | 0 |
| Shared graph: snapshot hashing | 877.630 | 0 | 0 |
| Shared graph: snapshot and warm cache hit | 2,865.644 | 0 | 1 |
| Eviction, working set of 129 | 159.904 | 1,000 | 128 |

Warmup performed 64 calculations for typed warm hits and one each for irrelevant changes, large payloads, and the shared graph's cache phase. Those calculations are outside the reported loops. Runtime checks accepted the expected computation counts. Direct calculation and typed warm hits produced the same accumulated result; cold misses and relevant changes also matched each other.

Typed warm hits took longer than direct calculation in this sample. Hashing the typed key took longer than forming it. The runtime graph's hashing and cache phases took longer than the concrete-key path for this workload. That graph contains more structure and two content occurrences, so these timings do not isolate type-erasure overhead. Shared-source capture avoids repeated provider reads within a request; it does not eliminate hashing repeated structural occurrences. These observations do not predict performance for another computation or key representation.

## Memory and measurement limits

The separate process high-water RSS reports ranged from 6,406,144 to 7,110,656 bytes. Cold misses reached the maximum; typed warm hits reported 6,438,912 bytes, the large-payload case 6,733,824 bytes, and the shared-source process 6,602,752 bytes. The shared-source number covers all three phases together. RSS includes process startup, setup, temporary objects, and output; it is not retained cache memory.

The cold cache held 1,000 entries referencing 4,096,000 logical payload bytes, but those keys shared one 4,096-byte content buffer. Its result values accounted for 8,000 bytes. The 128-entry bounded caches referenced 524,288 logical payload bytes through that same 4,096-byte buffer, with 1,024 bytes of result values. These counts exclude dictionary and LRU storage, headers, labels, spare capacity, erased nodes, and allocator overhead. The input also retained the buffer. Total retained key bytes and allocation counts were not measured.

Each case ran once, consecutively, with no controlled power or system-load experiment. Small timings are sensitive to loop overhead and scheduling. Repeated comparable runs and application profiling are needed before choosing a cache or projection.

## Source fingerprints

The runner captured per-file SHA-256 digests alongside the raw JSON and `/usr/bin/time -l` reports. The principal implementation fingerprints for this run were:

```text
a2928b787ad083d3656822879c05e7d58c174bc2fdccc9f114eb40293c71fbd6  Sources/DerivedKeysBenchmarks/Benchmark.swift
b7ef51ab1dcd65924374b2cd903e1836751f191a147c77c6b889998ef90b49ad  Sources/DerivedKeys/MemoizationCache.swift
42aa3d1690d59cb0f605345b8e5dd8f32d5e98a800f9dd909e7e0aeb0eb7f615  Sources/DerivedKeys/KeyProjection.swift
26c8c2e208c3b73107ddbd11fb35d8f5336b798c8082cd049a6f0e1fb999447d  Sources/DerivedKeys/KeySource.swift
103c87ab4a381e27684c476fcf7d8f7a9dbe0a4ed855fd00523d59273d54f096  Sources/DerivedKeys/KeyValueProvider.swift
```

Later source changes can produce different results. Run the suite again for the candidate being evaluated rather than treating these numbers as a performance guarantee.
