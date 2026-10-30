# UIKit string representation results

Select an authoritative Swift model value when the application already owns and synchronizes its text. In this **iOS Simulator** sample, the long-ASCII warm `SizeCache` request takes **3.56 µs** with model text versus **149.75 µs** reading `UITextView.text`. Hashing just the pre-read strings takes **1.26 versus 62.98 µs**. These results support measuring representation costs before changing cache storage or replacing full semantic values with revision keys. The `SizeCache` core and public APIs are unchanged.

Per-request `makeContiguousUTF8()` reduces that warm lookup to **36.70 µs**, but its getter and conversion phase alone takes **33.02 µs**. This is a diagnostic alternative, not a recommendation to normalize every dependency automatically. Hashing model text still has a cost: the long non-ASCII string takes **7.80 µs** in the string-only phase. See the [authoritative-model selection guide](../Examples/Size-Caches.md#select-authoritative-model-text) for the synchronization contract.

This run was recorded on 2026-10-28 local time (2026-10-29 UTC). **No physical-device measurements are available.** The [full benchmark guide](README.md) describes reproduction and dependency selection; the [raw trials and source fingerprints](Measurements/UIKit-Strings-2026-10-28-Simulator.json) preserve this run. The existing [UIKit sizing results](UIKit-Results.md) remain a separate baseline for labels, text views, and composed document sizing; this string fixture does not update those results.

## Compared paths and timing boundaries

All four arms fit a real, equally configured `UITextView`: 17-point system font, noneditable and nonselectable, scrolling disabled, left-to-right layout, zero text insets and line-fragment padding, word wrapping, and a 180-point width with unconstrained height. Text is constructed in Swift before timing. Each independent fixture stores both the model text and the same value assigned to UIKit.

| Arm | Measured operation |
| --- | --- |
| Direct | `UITextView.sizeThatFits` on the retained control, preserving UIKit's own warm state |
| UIKit text | `SizeCache.size`, selecting `textView.text` and `textView.font` |
| Model text | `SizeCache.size`, selecting `model.text` and `textView.font` |
| Contiguous UIKit text | `SizeCache.size`, selecting a getter that reads `textView.text ?? ""`, calls `makeContiguousUTF8()`, and returns the value; also selects the font |

The UIKit key path selects `String?`; the model and contiguous getters select `String`. Thus the complete-request comparison includes this optional-key difference. The string-only hash diagnostic unwraps the UIKit value outside timing and hashes nonoptional `String` values in all three paths, giving a more focused representation comparison. All paths preserve complete text values rather than hashes alone.

Each trial creates independent fixtures and preallocated result buffers. Every arm receives eight warmup fits; cached arms use seven direct fits and one cache-seeding fit. Four-arm execution order rotates by trial.

Repeated-warm requests perform no setters. Mutation and mixed requests include identical assignments to **both** `model.text` and `UITextView.text` before every request in every arm, followed by the complete direct fit or cache request. That includes assignments for adjacent repeats. Cached requests include dependency reads, selected per-request conversion, snapshot creation, hashing, equality, lookup, and fitting on a miss. Buffer writes and timer/loop overhead are included.

View creation, native input construction, buffer allocation, validation, diagnostics, and serialization are outside timing. There are no timed counters. Work is synchronous on the main actor; these are sizing measurements, not rendering, frame assignment, or scrolling measurements.

## Complete requests

Each cell is **median [minimum–maximum] µs/request**, calculated across nine trial loop means of 128 requests. Ratios divide separate medians; below 1 favors model text over the named comparison. Ranges describe observations, not confidence intervals.

| Content | Scenario | Direct | UIKit text | Model text | Contiguous UIKit text | Model / UIKit | Model / direct |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Short ASCII | Repeated warm | 114.84 [110.22–516.06] | 5.88 [5.66–6.05] | 2.33 [2.32–2.38] | 3.33 [3.31–208.60] | 0.397× | 0.020× |
| Short ASCII | Mutation and return | 1,464.77 [709.25–2,605.83] | 475.36 [332.14–968.99] | 505.50 [362.14–2,726.24] | 728.33 [353.56–3,643.49] | 1.063× | 0.345× |
| Short ASCII | Mixed, capacity 16 | 897.25 [841.19–1,264.07] | 841.08 [731.31–6,279.86] | 744.32 [642.59–1,096.39] | 816.46 [682.66–1,098.87] | 0.885× | 0.830× |
| Long ASCII | Repeated warm | 838.96 [803.79–889.66] | 149.75 [149.48–166.92] | 3.56 [3.46–3.87] | 36.70 [36.35–41.38] | 0.024× | 0.004× |
| Long ASCII | Mutation and return | 9,099.80 [7,246.85–30,180.56] | 8,404.70 [6,556.46–20,382.03] | 7,911.21 [6,191.25–15,222.78] | 8,553.38 [6,540.97–17,487.74] | 0.941× | 0.869× |
| Long ASCII | Mixed, capacity 16 | 4,281.98 [4,188.21–4,941.06] | 4,147.90 [4,052.39–4,651.03] | 3,784.02 [3,729.24–4,779.89] | 3,794.17 [3,691.46–4,142.19] | 0.912× | 0.884× |
| Long non-ASCII | Repeated warm | 1,391.00 [1,349.24–1,438.43] | 139.54 [138.93–152.72] | 10.07 [10.02–11.49] | 58.59 [58.27–64.76] | 0.072× | 0.007× |
| Long non-ASCII | Mutation and return | 5,379.31 [5,278.50–5,877.60] | 4,085.89 [4,023.01–4,626.85] | 3,910.20 [3,874.36–4,143.66] | 3,959.88 [3,931.86–4,241.35] | 0.957× | 0.727× |
| Long non-ASCII | Mixed, capacity 16 | 3,899.55 [3,815.62–4,051.02] | 3,513.15 [3,482.23–3,561.55] | 3,149.82 [3,105.74–3,240.29] | 3,207.30 [3,144.22–3,282.12] | 0.897× | 0.808× |

Warm requests show the clearest representation effect because they exclude setters and miss fitting. Mutation and mixed rows include UIKit invalidation and remeasurement as well as dependency work; their improvements are smaller, and several ranges are wide. The short-ASCII mutation row has a higher model median than the UIKit-text median. This sample does not establish a universal benefit for every content size or workload.

## Component observations

These separate phases use five trials of 512 operations on warmed fixtures. Getter and capture phases write preallocated 64-slot buffers; the hash phases use 64 pre-read strings or preconstructed snapshots and accumulate public `hashValue` results through a non-inlined call. Snapshot capture selects the actual text and font dependencies. Getter/conversion work is outside the hash-only phases.

The fixed order is dependency read, snapshot capture, string hash, then snapshot hash. Buffers are initialized and validation may traverse, compare, or hash values before later phases. These observations therefore describe warmed values, not untouched cold representations. Different observation overheads and phase state make them **nonadditive**: subtracting them from full lookup cannot isolate equality or LRU work.

Each cell is **median [minimum–maximum] µs/operation**.

| Content | Selected text | Dependency read | Snapshot capture | Pre-read String hash | Preconstructed snapshot hash |
| --- | --- | ---: | ---: | ---: | ---: |
| Short ASCII | UIKit text | 0.253 [0.253–0.672] | 1.600 [1.588–1.626] | 0.994 [0.991–3.849] | 1.283 [1.250–3.678] |
| Short ASCII | Model text | 0.005 [0.005–0.006] | 1.174 [1.168–1.193] | 0.037 [0.037–0.038] | 0.226 [0.225–0.228] |
| Short ASCII | Contiguous UIKit text | 0.885 [0.881–0.904] | 2.094 [2.082–2.114] | 0.037 [0.036–0.037] | 0.226 [0.225–0.230] |
| Long ASCII | UIKit text | 0.336 [0.330–0.365] | 1.649 [1.590–1.828] | 62.977 [62.038–67.064] | 61.653 [61.553–68.318] |
| Long ASCII | Model text | 0.005 [0.005–0.006] | 1.128 [1.127–1.167] | 1.258 [1.258–1.293] | 1.429 [1.428–1.440] |
| Long ASCII | Contiguous UIKit text | 33.021 [32.983–36.375] | 34.382 [34.289–35.194] | 1.258 [1.248–1.261] | 1.436 [1.427–1.444] |
| Long non-ASCII | UIKit text | 0.333 [0.331–0.337] | 1.591 [1.588–1.621] | 67.551 [67.066–74.522] | 67.609 [67.298–72.807] |
| Long non-ASCII | Model text | 0.005 [0.005–0.005] | 1.134 [1.129–1.135] | 7.795 [7.792–7.831] | 7.993 [7.984–8.065] |
| Long non-ASCII | Contiguous UIKit text | 48.637 [47.978–50.479] | 49.697 [49.073–49.777] | 7.805 [7.802–7.810] | 8.009 [8.001–8.033] |

The raw UIKit getter is inexpensive here (about 0.25–0.34 µs), while hashing its pre-read long strings is much more expensive. This localizes a representation-related cost beyond the getter itself without assigning the remaining full-lookup time to a particular cache operation. Converting UIKit text moves work into every dependency read; retaining the already-constructed model value avoids that conversion in this fixture.

### Initial representation observations

The fixture records public `isContiguousUTF8` flags before warmup, equality, UTF-8 traversal, or hashing. For every content case, the constructed Swift source is contiguous, the raw UIKit getter is not contiguous, the selected model value is contiguous, and the selected normalized value is contiguous. Initial variant lengths are 30 UTF-8 bytes for short ASCII, 1,619 for long ASCII, and 1,739 for long non-ASCII.

These flags describe these constructed values on this runtime. A Swift model property does not guarantee native or contiguous storage: a model populated from bridged text can retain a different representation. The property name and value type alone do not establish the cost.

## Correctness and bounded reuse

Timed results in all four arms match exactly for every request, with finite positive sizes and matching checksums. An untimed replay counts actual measurement-closure executions and compares cache behavior with an independent integer-identity LRU replay. Observations below apply to every content case and cached strategy; warmup is excluded.

| Trace | Requests | Hits / misses | Cached fits | Direct fits | Final entries | Eviction observed |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Repeated warm | 128 | 128 / 0 | 0 | 128 | 1 | No |
| Mutation and return | 128 | 124 / 4 | 4 | 128 | 5 | No |
| Mixed, capacity 16 | 128 | 65 / 63 | 63 | 128 | 16 | Yes |

The mutation trace repeats A–B–A–C–A–D–A–E. It verifies that B changes the fitted height, returning to A restores A's size, and that return hits the cache. The mixed trace repeats each of 40 variants twice before cycling; capacity remains 16 rather than growing with iteration count. Actual eviction is observed and every entry count stays within capacity. Model and UIKit text equality is checked during the replay, outside timing.

## Environment and evidence limits

| Setting | Value |
| --- | --- |
| Destination | iPhone 18 Pro Simulator, arm64; iOS 27.0 (24A434) |
| Host | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB |
| Host OS | macOS 27.2 (26B123) |
| Toolchain | Xcode 27.1 (27A9275); Apple Swift 6.4, `swiftlang-6.4.0.34.1`, `clang-2100.3.34.1` |
| Build | Release, Swift 6 mode; iOS Simulator 27.1 SDK; iOS 16 package minimum |
| Instrumentation | Coverage and parallel testing disabled; no allocation profiling |
| Sampling | Nine rotating-order trials × 128 complete requests; five trials × 512 operations per component phase |
| Cache | Capacity 16, independent fixture/cache per arm and trial |

The [XCTest fixture](../Tests/DerivedKeysUIExampleTests/UIKitStringBenchmarkTests.swift) defines the exact inputs, settings, traces, and assertions. The runner validated one executed case, all 36 complete-request rows, all 36 component rows, all nine representation observations, checksums, result equivalence, and cache diagnostics. Source fingerprints were unchanged across the run. The candidate was `e9674f9fb6bc9f54968043fd1070f9fa04cc55c0` with uncommitted changes; the raw export retains the recorded source hashes and original attachment SHA-256. Its hash identifies the original attachment, which included a runtime device name; the exported copy removes that name and excludes device identifiers and private local paths.

No other heavy build or benchmark job ran concurrently with the timed run. Background load, thermal state, and power conditions were not controlled. The ranges do not establish statistical significance; no allocation counts or memory savings are claimed. Simulator timings cannot establish physical-device performance.

A physical-device attempt built successfully but produced no measurements: test execution reported, “Tool-hosted testing is unavailable on device destinations. Select a host application … simulator destination instead.” A hosted device test setup is required before adding a separate physical-device comparison.
