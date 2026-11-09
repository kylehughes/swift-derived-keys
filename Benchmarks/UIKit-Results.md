# UIKit sizing results

This is a historical recipe-based run, predating the native-fitting leaf caches and bound parent handles. Its document children selected parent-root model dependencies and configured controls through getters. The current example and methodology have since moved to actual-control dependencies and eager configuration; these timings do not measure that implementation. The recorded source fingerprints remain the provenance for this sample. See the [native-fitting results](UIKit-Native-Fitting-Results.md) for the updated example and the [specialization results](Specialization-Results.md) for the latest comparison.

In this **iOS Simulator** sample, caching substantially reduces repeated sizing time for the document example: a warm composed parent takes **6.00 µs** through DerivedKeys versus **271.91 µs** for direct child fitting and combination. A parent-only spacing change takes **12.88 versus 322.38 µs**, reusing both child measurements. Caching is a poor fit for the already-warm labels here: direct fitting takes about **0.11 µs**, while a cache hit takes **3.80–4.04 µs**.

Shared results help the multiline and attributed label pools, but not the single-line pool. The mixed-request results are less decisive: the document parent's median time is about 7% lower with caching, while `UITextView`'s is about 5% higher. Several mixed rows have overlapping ranges or inconsistent paired wins. Choose caching for the application's avoided work and reuse rate, not simply because it reduces measurement calls.

These observations come from one Simulator run, recorded on 2026-10-28. **No physical-device results are reported.** The [raw trials, diagnostics, and source fingerprints](Measurements/UIKit-2026-10-28.json) preserve this run. The [benchmark guide](README.md) describes the current methodology and reproduction commands; the timing boundaries below describe this historical run.

## Environment and timing boundaries

| Setting | Value |
| --- | --- |
| Destination | iPhone 18 Pro Simulator, arm64; iOS 27.0 (24A434) |
| Host hardware | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB |
| Host OS | macOS 27.2 (26B123) |
| Toolchain | Xcode 27.1 (27A9275); Apple Swift 6.4, `swiftlang-6.4.0.34.1`, `clang-2100.3.34.1` |
| Build | Release, Swift 6 mode, iOS Simulator 27.1 SDK, iOS 16 package minimum; coverage and parallel testing disabled |
| Primary sampling | Nine paired trials of 128 requests per arm; arm order alternates |
| Storage and ownership | Independent direct/cached fixtures each trial; one shared cache per recipe; capacity 16 per cache |
| Warmup | One cache-seeding request, then four direct UIKit fits; equivalent pools warm a separate seed only |
| Inputs | Short, multiline, long, and attributed content; 17/24/32-point standalone fonts; three document Dynamic Type categories; 180/320-point widths |

Warm and equivalent-pool rows time **measurement only** on preconfigured controls. The equivalent pool has eight initially unfitted request views and one separately fitted seed; those eight views are reused throughout the 128-request loop. It is not a fresh-view-per-request experiment.

Changing rows include the applicable assignments plus measurement in both arms. Content and font/category values are prebuilt; width changes only change the proposal, and parent-only changes only assign spacing. The document uses the actual example's child handles and parent recipe. Its changing direct path uses the same synchronized child getters; warm direct fitting retains configured controls to preserve UIKit's own internal caches. The parent transforms the outer width by subtracting 12-point padding on each side and fits the children with unconstrained height.

View creation, input generation, buffer allocation, result comparison, cache diagnostics, and serialization are outside timing. Buffer writes and loop/timer overhead are included. These measurements cover sizing and size combination, not frame assignment, rendering, or scrolling. All work is synchronous on the main actor.

## All paired measurements

Each timing is **median [minimum–maximum] microseconds per request**, calculated from each trial's loop mean. The ratio divides the cached median by the direct median; below 1 favors caching. The final column counts trials where the cached arm was faster than its paired direct arm. A ratio of separate medians can disagree with that majority when trials vary substantially; neither is a confidence interval.

### UILabel-single-line

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 [0.11–0.12] | 4.03 [4.00–4.12] | 35.329× | 0/9 |
| Equivalent view pool | 1.46 [1.29–2.34] | 4.06 [4.02–4.17] | 2.786× | 0/9 |
| Width changes | 0.12 [0.12–0.13] | 4.33 [4.28–6.10] | 35.432× | 0/9 |
| Content/font changes | 605.44 [162.38–1,008.18] | 29.75 [27.36–2,568.21] | 0.049× | 8/9 |
| Mixed, capacity 16 | 330.23 [130.30–1,204.39] | 215.21 [140.66–926.08] | 0.652× | 3/9 |

### UILabel-multiline

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 [0.11–0.13] | 4.04 [4.02–21.47] | 36.218× | 0/9 |
| Equivalent view pool | 18.23 [13.03–1,166.57] | 4.09 [4.04–4.30] | 0.224× | 9/9 |
| Width changes | 0.59 [0.57–0.90] | 4.86 [4.84–245.85] | 8.215× | 0/9 |
| Content/font changes | 958.01 [420.00–1,964.21] | 52.14 [50.71–324.93] | 0.054× | 9/9 |
| Mixed, capacity 16 | 492.08 [326.27–922.25] | 430.44 [337.02–609.37] | 0.875× | 5/9 |

### UILabel-attributed

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 [0.11–0.12] | 3.80 [3.77–3.83] | 33.846× | 0/9 |
| Equivalent view pool | 12.77 [12.64–12.98] | 3.81 [3.81–3.85] | 0.298× | 9/9 |
| Width changes | 0.62 [0.61–0.70] | 4.60 [4.57–4.75] | 7.466× | 0/9 |
| Content/font changes | 506.30 [372.76–994.63] | 61.14 [57.93–252.35] | 0.121× | 9/9 |
| Mixed, capacity 16 | 403.50 [382.68–437.90] | 358.62 [319.79–418.54] | 0.889× | 8/9 |

### UITextView

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 5,415.01 [848.90–22,925.97] | 742.12 [157.49–7,222.66] | 0.137× | 9/9 |
| Equivalent view pool | 2,231.51 [1,359.67–6,621.64] | 301.83 [156.50–1,081.69] | 0.135× | 9/9 |
| Width changes | 2,086.10 [998.00–5,078.81] | 244.06 [171.76–3,509.93] | 0.117× | 8/9 |
| Content/font changes | 3,655.11 [3,011.54–5,895.80] | 2,705.92 [2,364.49–3,965.37] | 0.740× | 7/9 |
| Mixed, capacity 16 | 2,494.12 [2,242.42–3,488.31] | 2,622.68 [2,452.35–4,158.52] | 1.052× | 3/9 |

### DocumentContentView-text

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 349.18 [291.10–567.43] | 3.07 [2.92–4.81] | 0.009× | 9/9 |
| Equivalent view pool | 382.45 [302.47–592.93] | 3.13 [2.95–14.03] | 0.008× | 9/9 |
| Width changes | 371.75 [358.63–428.15] | 6.69 [6.19–7.64] | 0.018× | 9/9 |
| Content/font changes | 2,977.74 [2,817.13–3,557.58] | 348.24 [317.15–507.81] | 0.117× | 9/9 |
| Mixed, capacity 16 | 2,099.88 [2,081.65–2,191.24] | 1,991.91 [1,947.39–2,020.56] | 0.949× | 9/9 |

### DocumentContentView-button

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 5.60 [5.58–5.67] | 1.35 [1.34–1.39] | 0.241× | 9/9 |
| Equivalent view pool | 5.61 [5.59–6.00] | 1.37 [1.35–1.52] | 0.244× | 9/9 |
| Width changes | 10.44 [10.21–10.79] | 1.83 [1.74–1.85] | 0.176× | 9/9 |
| Content/font changes | 59.22 [58.82–67.73] | 41.92 [41.73–48.15] | 0.708× | 9/9 |
| Mixed, capacity 16 | 51.81 [50.84–58.28] | 36.11 [35.80–41.02] | 0.697× | 9/9 |

### DocumentContentView-parent

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm parent | 271.91 [269.87–306.67] | 6.00 [5.74–8.14] | 0.022× | 9/9 |
| Equivalent view pool | 277.09 [272.40–313.44] | 5.87 [5.76–6.67] | 0.021× | 9/9 |
| Parent-only spacing | 322.38 [316.86–353.12] | 12.88 [12.55–14.89] | 0.040× | 9/9 |
| Width changes | 325.17 [323.03–371.65] | 8.96 [8.78–10.95] | 0.028× | 9/9 |
| Content/font changes | 2,552.86 [2,495.00–2,588.93] | 262.38 [260.73–314.67] | 0.103× | 9/9 |
| Mixed, capacity 16 | 2,204.75 [2,121.84–2,392.88] | 2,051.56 [1,989.14–2,222.96] | 0.931× | 8/9 |

## Hits, misses, and measurement counts

The following observations come from an **untimed replay**, not counters in the timed loops. Standalone control misses are counted measurement-closure executions. For the actual document bundle, key membership is observed by replaying exact prefixes and probing with public removal/count operations; measurement counts are inferred from those misses. A parent hit performs no child probe or calculation. Direct paths measure the requested leaf on every request; the direct parent measures both children and combines them 128 times.

For every leaf workload, warm and equivalent-pool requests yield **128 hits / 0 misses**, with one retained entry. Alternating widths yield **127 / 1**, with two entries. Content/font changes yield **117 / 11**, with 12 entries, except the fixed-title document button: **126 / 2**, with three entries. Unchanged content is deliberately absent from the button's dependencies.

| Mixed workload | Hits / misses | Hit rate | Final entries | Eviction observed |
| --- | ---: | ---: | ---: | --- |
| Single-line label | 25 / 103 | 19.5% | 16 | Yes |
| Multiline label | 24 / 104 | 18.8% | 16 | Yes |
| Attributed label | 24 / 104 | 18.8% | 16 | Yes |
| Text view | 24 / 104 | 18.8% | 16 | Yes |
| Document text | 24 / 104 | 18.8% | 16 | Yes |
| Document button | 123 / 5 | 96.1% | 6 | No; its six width/category keys fit |

The mixed trace contains 40 semantic variants in a repeating 48-request cycle, with eight adjacent-repeat pairs followed by 32 distinct requests. Capacity stays 16 regardless of iteration count, so the content-dependent rows cannot retain the entire working set.

For the composed document, counts are shown separately for each cache. Child counts include only calls made on parent misses:

| Scenario | Parent hits / misses | Text hits / misses | Button hits / misses | Final parent / text / button entries |
| --- | ---: | ---: | ---: | ---: |
| Warm parent | 128 / 0 | 0 / 0 | 0 / 0 | 1 / 1 / 1 |
| Equivalent view pool | 128 / 0 | 0 / 0 | 0 / 0 | 1 / 1 / 1 |
| Parent-only spacing | 0 / 128 | 128 / 0 | 128 / 0 | 16 / 1 / 1 |
| Width changes | 127 / 1 | 0 / 1 | 0 / 1 | 2 / 2 / 2 |
| Content/font changes | 117 / 11 | 0 / 11 | 9 / 2 | 12 / 12 / 3 |
| Mixed | 24 / 104 | 0 / 104 | 99 / 5 | 16 / 16 / 6 |

Parent-only spacing changes evict parent entries while preserving the two child results. Mixed requests evict parent and text entries. Each width miss uses the actual transformed child proposal. All direct/cached sizes matched exactly; observed entry counts stayed within capacity.

## Remaining lookup costs

Separate phases on warmed fixtures locate costs that remain after the [concrete erasure repair](Erasure-Results.md). Each phase uses five trials of 512 operations, in fixed phase order on the same view. Capture and text-getter phases write 64 observation slots, hash phases accumulate values, and fitting/lookup phases write preallocated size buffers. Their observation costs are included, so these are **not additive components** and subtraction does not isolate equality or LRU cost.

| Workload | Phase | µs/operation |
| --- | --- | ---: |
| UILabel-single-line | Warm UIKit fit | 0.082 [0.082–0.082] |
| UILabel-single-line | Dependency capture | 2.047 [2.042–2.051] |
| UILabel-single-line | Preconstructed snapshot hash | 0.321 [0.321–0.324] |
| UILabel-single-line | Full warm lookup | 3.657 [3.648–3.663] |
| UILabel-multiline | Warm UIKit fit | 0.082 [0.081–0.082] |
| UILabel-multiline | Dependency capture | 2.040 [2.036–2.044] |
| UILabel-multiline | Preconstructed snapshot hash | 0.476 [0.474–0.479] |
| UILabel-multiline | Full warm lookup | 3.815 [3.804–3.822] |
| UILabel-attributed | Warm UIKit fit | 0.082 [0.081–0.082] |
| UILabel-attributed | Dependency capture | 1.999 [1.994–2.008] |
| UILabel-attributed | Preconstructed snapshot hash | 0.343 [0.341–0.345] |
| UILabel-attributed | Full warm lookup | 3.568 [3.564–3.573] |
| UITextView | Warm UIKit fit | 827.733 [818.180–860.434] |
| UITextView | Dependency capture | 1.449 [1.440–1.490] |
| UITextView | Preconstructed snapshot hash | 61.483 [60.813–67.557] |
| UITextView | Full warm lookup | 151.799 [147.572–156.956] |
| UITextView | Text getter | 0.315 [0.308–0.334] |

For these warmed labels, dependency capture alone costs about 2 µs, already more than the approximately 0.08 µs direct fit in the diagnostic. Even very cheap hashing or storage cannot recover that difference. This explains why fewer UIKit calls do not help the warm-label rows.

The long-text `UITextView` fixture has a different cost profile: snapshot hashing takes about 61 µs, compared with 1.45 µs for capture and 0.32 µs for the text getter. The getter accounts for little of the observed cost. Full lookup also includes equality and storage work; these phases do not assign exact shares to them. Its 152 µs warm lookup is still below its 828 µs warm fit in this separate phase. Hashing full content remains real work, even though the array-erasure defect is repaired.

The primary `UITextView` rows and this later diagnostic show substantial timing variation, so the diagnostic does not explain every end-to-end outlier. The mixed text-view trace misses on 104 of 128 requests and is slower by median: those misses perform measurement plus cache work. Single-line and multiline mixed-label comparisons also fail to establish a consistent benefit in this sample. The document text's mixed trace shows a small reduction; its warm/shared rows and the warm composed parent show much larger gains.

The [string-representation follow-up](String-Results.md) compares the UIKit getter with identical native model text and includes conversion costs in complete requests. It confirms substantially cheaper repeated lookups when selecting the existing model value, without changing the cache implementation. Start with that comparison before considering compact identity and revision properties under the [complete revision contract](../Examples/Size-Caches.md#consider-a-compact-projection-after-measuring). Ordinary stable values remain supported, and no custom wrapper is required to obtain the concrete-erasure repair. UIKit's own warmed behavior should remain the baseline when deciding whether another cache is worth its cost.

## Scope and reproducibility

Run `python3 Benchmarks/run-uikit.py` with the documented toolchain to collect a new Simulator sample of the current implementation. The current tool-hosted package scheme cannot execute on a physical device without a host application; see the [runner limitation](README.md#run-on-a-device-or-simulator). The current [XCTest fixture](../Tests/DerivedKeysUIExampleTests/UIKitSizingBenchmarkTests.swift) has evolved since this run; it is not an exact historical source snapshot. This run used the source fingerprints in the raw JSON, on top of `7adad7c311ab773fa234f4788badb345ea9ee91e` with uncommitted changes.

The final runner validated one executed XCTest case, all 36 primary rows, all 17 diagnostic rows, checksums, result equivalence, and cache observations. It retained the xcresult and command logs and deleted its owned Simulator. No other build or benchmark job ran concurrently with the timed run. Background system load, thermal state, and power conditions were not controlled; several ranges are wide. No statistical significance, allocation count, or memory measurement is claimed. Simulator CPU timings cannot establish physical-device or scrolling performance.
