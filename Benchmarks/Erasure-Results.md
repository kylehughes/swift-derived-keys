# Concrete dependency erasure

The internal representation repair reduced the synthetic warm parent lookup from **2,658 to 83 µs per request**, about **32× faster**, in five before/after trials on 2026-10-28. The direct synthetic calculation still took about **42 µs**. The change removes an internal bottleneck, but does not establish that caching is always useful. For current application-sizing measurements, start with the [native-fitting results](UIKit-Native-Fitting-Results.md); the [UIKit benchmark guide](README.md) describes the methodology and other reports.

## What changed

`DependencySnapshot` previously passed selected values directly to `AnyHashable`. For arrays, that selects an element-erased path instead of retaining the array's concrete operations. The snapshot now stores the value in a private generic `Hashable` wrapper before erasing it. All three `KeySource` leaf constructors use that same initializer.

The wrapper retains complete values and invokes their concrete hashing and equality. The existing concrete-type discriminator, labels, child order, multiplicity, and nesting remain part of equality. This is not a stored integer hash or a caller-visible wrapper. The key-path API, recipe ownership, cache storage, and deployment minimums are unchanged.

Regression tests cover arrays sharing storage, equal arrays with separate storage, value/order/multiplicity/element-type distinctions, and equivalence between direct snapshots and all source constructors. Existing collision, stable-snapshot, lifetime, and composition tests also pass. Shared-storage array equality now takes the native fast path without comparing every element; hashing still inspects content when the value's own implementation requires it.

## Before and after

Values are **median [minimum–maximum] microseconds per operation** across five trials. Ratios divide the optimized median by the baseline median; lower is better. Each trial is a fresh process with 1,000 operations, 4,096 bytes per payload, and capacity 128. The paired cases alternate baseline/optimized order between trials.

| Diagnostic | Before, µs/op | After, µs/op | After / before |
| --- | ---: | ---: | ---: |
| Size cache: warm parent | 2,657.94 [2,645.38–2,671.22] | 83.05 [82.92–84.62] | 0.031× |
| Size calculation: direct | 42.33 [42.00–43.14] | 42.26 [42.05–43.26] | 0.998× |
| Shared source: snapshot capture | 1.76 [1.74–1.82] | 1.91 [1.88–1.93] | 1.090× |
| Shared source: snapshot hashing | 838.33 [830.54–863.37] | 77.65 [76.63–81.47] | 0.093× |
| Shared source: warm lookup | 2,650.31 [2,644.23–2,678.66] | 79.71 [78.57–80.85] | 0.030× |

The shared-source graph uses one payload in two structural branches. Its hashing and warm lookup improve, while snapshot capture alone becomes slightly more expensive in this sample. Capture does not hash the contents; the substantial gain appears in the cost of erased hashing and equality.

The size graph contains a parent and two children. A warm parent hits one unchanged request. The direct diagnostic uses the same child math with varying input variants, as does the cold trace; it is a separate cost diagnostic, not an identical request trace to the warm-parent case. Warm-parent lookup remains about twice as costly as that direct calculation.

| Optimized size diagnostic | µs/op | Parent / left / right calculations |
| --- | ---: | --- |
| Snapshot capture | 4.36 [4.30–4.52] | 0 / 0 / 0 |
| Parent miss, warm children | 488.07 [471.29–506.08] | 1,000 / 0 / 0 |
| Cold composed request | 865.17 [843.17–889.81] | 1,000 / 1,000 / 1,000 |

The parent-miss trace changes spacing while retaining the child inputs and proposals. It avoids child calculation but still captures and looks up parent and child snapshots and inserts the parent result. The cold trace changes both children and pays for the complete cache path and calculation. Both fill and evict bounded storage.

Warm parent calculations are 0 / 0 / 0 after one warmup calculation per cache. The direct trace performs 1,000 calculations at every level; cold and direct checksums match. The existing executable enforces counts and result checks.

## Reproduce and interpret

These are macOS **SwiftPM Release** results: Apple M1 Max, MacBookPro18,2, 10 logical CPUs, 64 GiB; macOS 27.2 (26B123), arm64; Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), driver 1.168.6. Swift 6 mode, tools 6.4, and the macOS 13 package minimum were preserved.

The baseline is the task-entry source at `7adad7c311ab773fa234f4788badb345ea9ee91e`, including the existing README reorganization. Only `DependencySnapshot.swift` and `KeySource.swift` differ among measured build inputs. The [raw observations and source/binary SHA-256 fingerprints](Measurements/Erasure-2026-10-28.json) distinguish both builds.

Build the baseline and optimized source separately with `swift build -c release --product DerivedKeysBenchmarks`, then run each executable with the same arguments, alternating their order over five trials:

```sh
DerivedKeysBenchmarks --case size-warm-parent --iterations 1000 --payload-bytes 4096 --capacity 128
DerivedKeysBenchmarks --case size-direct --iterations 1000 --payload-bytes 4096 --capacity 128
DerivedKeysBenchmarks --case shared-source --iterations 1000 --payload-bytes 4096 --capacity 128
```

The three additional optimized cases use `size-snapshot`, `size-parent-miss`, and `size-cold`. See the [synthetic methodology](Synthetic.md) for exact loop boundaries, warmup, counters, observation buffers, and checksum validation. No other build or benchmark job ran concurrently with these trials. Background system load and power conditions were not controlled; no confidence interval or timer-overhead correction is claimed.

No allocations or memory use were measured in this paired comparison. The raw result-value byte counts describe stored values only and exclude snapshots and storage overhead. Synthetic costs help locate regressions; they do not predict UIKit fitting or device performance.
