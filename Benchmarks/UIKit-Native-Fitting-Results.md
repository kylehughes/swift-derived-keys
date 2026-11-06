# UIKit sizing with native fitting

The native-fitting document example benefits from repeated reuse in this **iOS Simulator** run. A warm composed parent took **32.03 µs cached versus 276.33 µs direct**, about 88% less time. A spacing-only parent miss took **81.56 versus 277.48 µs**, reusing both child measurements. Each cached arm was faster in all nine paired trials for these two scenarios.

Caching did not help every workload. A warm button took **6.98 µs cached versus 5.80 µs direct**, and warm labels also favored UIKit's own fitting. The mixed document-parent trace took **2,319.54 versus 2,213.55 µs**, about 4.8% more time with caching; the cached arm won only one of nine pairs. Its parent hit rate was 18.8%, despite frequent button reuse.

This run was recorded on **2026-10-30**. It uses actual-control leaf caches and bound parent handles, with eager configuration and read-only control getters. The [raw trials, diagnostics, and source fingerprints](Measurements/UIKit-Native-Fitting-2026-10-30-Simulator.json) are retained. **No physical-device timings or allocation measurements are reported.** Some Simulator rows vary widely, so the ranges and paired wins matter alongside their medians.

## What this run measures

| Setting | Value |
| --- | --- |
| Destination | iPhone 18 Pro Simulator, arm64; iOS 27.0 (24A434) |
| Host | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB; macOS 27.2 (26B123) |
| Toolchain | Xcode 27.1 (27A9275); Swift 6.4, `swiftlang-6.4.0.34.1`, `clang-2100.3.34.1` |
| Build | Release, Swift 6 mode, iOS Simulator 27.1 SDK; iOS 16 minimum; coverage and parallel testing off |
| Sampling | Nine paired trials of 128 requests per arm; arm order alternates |
| Storage | Capacity 16 per cache, independent of request count; shared handles within each fixture |
| Warmup | Seed the cache, then four direct UIKit fits per warmed view; equivalent pools warm only a separate seed |
| Inputs | Short, multiline, long, and attributed content; 17/24/32-point standalone fonts; three document Dynamic Type categories; widths 180/320 points |

Each trial creates independent direct and cached fixtures. Warm rows measure already-configured controls. Equivalent-pool rows repeatedly use eight preconfigured, initially unfitted views after warming a separate seed; they do not create a new view for every request. Cached requests include dependency reads, snapshot construction, hashing, equality, and lookup. Native fitting performs no automatic String normalization.

Changing rows include the applicable configuration in both arms. In **document content/font and mixed rows**, this configures the whole document: assigning text and propagating category changes, which eagerly update control fonts. That work is included even when the row measures only the button. Those button rows therefore measure document configuration plus a button fit, not isolated button mutation. Width-only requests change the proposal; spacing-only requests assign spacing without changing child configuration.

The parent subtracts 12-point padding on each side and fits children with unconstrained height. The direct parent fits both children and combines their sizes on every request; the cached parent uses the example's bound handles.

View creation, prepared inputs, result-buffer allocation, equivalence checks, and diagnostic replay are outside timing. Loop/timer overhead and buffer writes are included. Frame assignment, rendering, and scrolling are outside this suite. All UIKit work runs synchronously on the main actor. See the [methodology and reproduction commands](README.md) for the complete workload contract.

The [2026-10-28 report](UIKit-Results.md) remains historical evidence for parent-root recipes and getter-driven configuration. This run changes dependencies and configuration timing, so the two reports are **not an isolated before/after measurement of binding overhead**. The older warm direct baseline already retained preconfigured controls.

## Paired measurements

Values are **median [minimum–maximum] µs per request**, using each trial's loop mean. Cached/direct is the ratio of those medians; below 1 favors caching. The last column counts cached wins within paired trials. Ranges are not confidence intervals, and the ratio of medians need not agree with a majority of paired wins.

### UILabel-single-line

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.12 [0.11–3.31] | 5.34 [4.09–8.99] | 44.924× | 0/9 |
| Equivalent view pool | 1.33 [1.27–2.52] | 3.94 [3.90–16.68] | 2.971× | 0/9 |
| Width changes | 0.12 [0.12–0.13] | 4.25 [4.21–7.92] | 35.253× | 0/9 |
| Content/font changes | 537.21 [191.40–1,059.21] | 28.28 [27.88–849.40] | 0.053× | 9/9 |
| Mixed, capacity 16 | 312.63 [132.02–1,998.47] | 927.53 [140.45–3,178.63] | 2.967× | 3/9 |

### UILabel-multiline

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 [0.11–11.16] | 4.22 [4.10–281.96] | 37.180× | 0/9 |
| Equivalent view pool | 57.63 [13.08–386.37] | 5.09 [4.17–220.48] | 0.088× | 8/9 |
| Width changes | 0.58 [0.57–0.71] | 4.88 [4.86–5.71] | 8.387× | 0/9 |
| Content/font changes | 1,048.97 [421.85–1,970.01] | 51.88 [50.85–1,036.57] | 0.049× | 7/9 |
| Mixed, capacity 16 | 397.40 [331.06–515.26] | 441.39 [345.06–638.02] | 1.111× | 3/9 |

### UILabel-attributed

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 [0.11–0.12] | 3.84 [3.81–3.98] | 33.925× | 0/9 |
| Equivalent view pool | 13.31 [12.78–85.86] | 3.91 [3.83–82.13] | 0.294× | 8/9 |
| Width changes | 0.78 [0.63–8.88] | 5.88 [4.67–20.87] | 7.561× | 2/9 |
| Content/font changes | 422.42 [400.82–673.09] | 60.10 [57.17–81.56] | 0.142× | 9/9 |
| Mixed, capacity 16 | 372.11 [363.36–395.06] | 321.05 [312.50–360.40] | 0.863× | 9/9 |

### UITextView

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 4,614.72 [834.03–29,426.48] | 1,345.69 [152.42–2,866.33] | 0.292× | 9/9 |
| Equivalent view pool | 2,337.57 [1,209.31–10,683.79] | 293.65 [155.50–1,989.87] | 0.126× | 9/9 |
| Width changes | 1,242.20 [949.18–4,549.37] | 226.10 [174.31–1,155.56] | 0.182× | 9/9 |
| Content/font changes | 3,672.03 [3,004.54–4,707.04] | 3,751.52 [2,397.92–4,652.75] | 1.022× | 4/9 |
| Mixed, capacity 16 | 2,454.04 [2,255.93–4,061.03] | 2,559.89 [2,250.10–3,239.51] | 1.043× | 3/9 |

The standalone text-view ranges are wide. Its warm end-to-end medians (4,614.72 µs direct and 1,345.69 µs cached) also differ substantially from the separate stable-input phases below (847.572 µs fitting and 149.515 µs full lookup). These observations do not isolate the cause of the discrepancy or establish a universal caching advantage for text views. Use the paired results, ranges, and application workload together.

### DocumentContentView-text

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 327.87 [273.20–402.74] | 23.69 [23.11–35.48] | 0.072× | 9/9 |
| Equivalent view pool | 305.79 [274.75–1,142.93] | 23.58 [23.27–26.17] | 0.077× | 9/9 |
| Width changes | 309.86 [284.53–389.99] | 28.99 [25.75–40.33] | 0.094× | 9/9 |
| Content/font changes | 2,438.05 [2,396.34–2,512.16] | 1,864.75 [1,781.73–1,896.83] | 0.765× | 9/9 |
| Mixed, capacity 16 | 2,226.28 [2,098.83–3,720.03] | 2,140.69 [2,092.00–2,324.20] | 0.962× | 8/9 |

### DocumentContentView-button

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 5.80 [5.75–6.88] | 6.98 [6.92–7.82] | 1.205× | 0/9 |
| Equivalent view pool | 5.84 [5.59–57.27] | 7.11 [6.84–17.70] | 1.218× | 2/9 |
| Width changes | 5.69 [5.54–6.32] | 7.14 [7.07–7.41] | 1.254× | 0/9 |
| Content/font changes | 2,024.51 [1,909.53–2,084.80] | 2,003.16 [1,907.73–2,058.48] | 0.989× | 6/9 |
| Mixed, capacity 16 | 1,459.44 [1,394.95–1,495.96] | 1,460.92 [1,404.33–1,481.13] | 1.001× | 3/9 |

### DocumentContentView-parent

| Scenario | Direct, µs/request | Cached, µs/request | Cached / direct | Cached faster trials |
| --- | ---: | ---: | ---: | ---: |
| Warm parent | 276.33 [271.98–285.10] | 32.03 [31.48–32.65] | 0.116× | 9/9 |
| Equivalent view pool | 285.77 [272.45–298.26] | 32.81 [32.16–35.98] | 0.115× | 9/9 |
| Parent-only spacing | 277.48 [272.77–283.83] | 81.56 [78.91–86.28] | 0.294× | 9/9 |
| Width changes | 288.72 [286.41–299.78] | 35.97 [34.31–37.99] | 0.125× | 9/9 |
| Content/font changes | 2,544.19 [2,478.38–2,650.33] | 1,891.18 [1,859.48–1,966.33] | 0.743× | 9/9 |
| Mixed, capacity 16 | 2,213.55 [2,183.21–2,332.25] | 2,319.54 [2,228.12–2,381.28] | 1.048× | 1/9 |

## Cache observations

Every direct/cached result matched exactly. Observed entries stayed within capacity. The following counts come from a separate **untimed replay**: standalone leaf measurement closures count misses; document membership is observed by replaying exact prefixes and probing public removal/count operations. Document measurement counts are inferred from those misses. No counters or destructive probes run inside the timed loops.

Warm and equivalent-pool leaf requests produced 128 hits and no misses after seeding. Alternating widths produced 127 hits and one miss. Content/font changes produced 117 hits and 11 misses, except the fixed-title document button, which produced 126 hits and two misses. Each requested direct leaf is fitted 128 times.

| Mixed leaf workload | Hits / misses | Hit rate | Final entries | Eviction observed |
| --- | ---: | ---: | ---: | --- |
| UILabel-single-line | 25 / 103 | 19.5% | 16 | Yes |
| UILabel-multiline | 24 / 104 | 18.8% | 16 | Yes |
| UILabel-attributed | 24 / 104 | 18.8% | 16 | Yes |
| UITextView | 24 / 104 | 18.8% | 16 | Yes |
| DocumentContentView-text | 24 / 104 | 18.8% | 16 | Yes |
| DocumentContentView-button | 123 / 5 | 96.1% | 6 | No |

The mixed trace cycles through 40 semantic variants in 48 requests: eight adjacent-repeat pairs followed by 32 distinct requests. Capacity 16 cannot retain the entire content-dependent working set. The button's six width/category keys fit without eviction.

Child counts below include only lookups on parent misses. A parent hit performs no child lookup. The direct parent fits both children and combines them on all 128 requests.

| Parent scenario | Parent hits / misses | Text hits / misses | Button hits / misses | Final parent / text / button entries |
| --- | ---: | ---: | ---: | ---: |
| Warm parent | 128 / 0 | 0 / 0 | 0 / 0 | 1 / 1 / 1 |
| Equivalent view pool | 128 / 0 | 0 / 0 | 0 / 0 | 1 / 1 / 1 |
| Parent-only spacing | 0 / 128 | 128 / 0 | 128 / 0 | 16 / 1 / 1 |
| Width changes | 127 / 1 | 0 / 1 | 0 / 1 | 2 / 2 / 2 |
| Content/font changes | 117 / 11 | 0 / 11 | 9 / 2 | 12 / 12 / 3 |
| Mixed, capacity 16 | 24 / 104 | 0 / 104 | 99 / 5 | 16 / 16 / 6 |

Spacing-only misses evicted parent entries while preserving child results. Mixed requests evicted parent and text entries; width misses used the actual transformed child proposals.

## Where lookup time goes

The same suite separately measures warmed fitting, dependency capture, hashing preconstructed snapshots, full lookup, and the text getter. Each phase uses five trials of 512 operations on stable inputs. Capture/getter phases write 64 observation slots, hashing accumulates values, and fitting/lookup phases write preallocated size buffers. Their observation costs are included. These phases are **not additive**; subtracting them does not isolate equality or LRU bookkeeping.

| Workload | Phase | µs/operation, median [range] |
| --- | --- | ---: |
| UILabel-single-line | Warm UIKit fit | 0.081 [0.081–0.082] |
| UILabel-single-line | Dependency capture | 2.118 [2.075–2.130] |
| UILabel-single-line | Preconstructed snapshot hash | 0.335 [0.327–0.369] |
| UILabel-single-line | Full warm lookup | 3.711 [3.680–3.775] |
| UILabel-multiline | Warm UIKit fit | 0.084 [0.083–0.084] |
| UILabel-multiline | Dependency capture | 2.116 [2.088–2.228] |
| UILabel-multiline | Preconstructed snapshot hash | 0.479 [0.473–0.557] |
| UILabel-multiline | Full warm lookup | 3.909 [3.894–4.098] |
| UILabel-attributed | Warm UIKit fit | 0.081 [0.081–0.082] |
| UILabel-attributed | Dependency capture | 2.089 [2.053–2.201] |
| UILabel-attributed | Preconstructed snapshot hash | 0.358 [0.346–0.360] |
| UILabel-attributed | Full warm lookup | 3.673 [3.640–3.908] |
| UITextView | Warm UIKit fit | 847.572 [837.637–877.628] |
| UITextView | Dependency capture | 1.510 [1.465–1.521] |
| UITextView | Preconstructed snapshot hash | 61.714 [61.629–61.943] |
| UITextView | Full warm lookup | 149.515 [149.026–150.539] |
| UITextView | Text getter | 0.328 [0.323–0.396] |

For warmed labels, dependency capture alone takes about 2.1 µs, compared with roughly 0.08 µs for a direct fit in these diagnostics. Caching cannot recover that difference for an unchanged label. Sharing semantic results across initially unfitted multiline and attributed views can help: those pool rows favored caching in eight of nine pairs, although several trials were noisy.

The standalone long-text snapshot takes 61.71 µs to hash, while a complete warm lookup takes 149.51 µs in the separate diagnostic. The text getter itself takes about 0.33 µs. This is consistent with the earlier [UIKit/model String representation comparison](String-Results.md); this run does not repeat that comparison or measure its model-backed alternative. When a model already owns authoritative text, the [custom model-backed recipe](../Examples/Size-Caches.md#select-authoritative-model-text) remains an option. Keep model and rendered state synchronized, and measure the selected values: a model property does not guarantee native or contiguous string storage. The convenience initializer does not make arbitrary dependency reads cheap or complete.

The document's native button lookup costs more than its warm direct fit in this run, even though it avoids every repeated measurement. A warm parent still benefits because it avoids text fitting and the whole combination. For parent-only misses, it pays for parent capture and child lookups again; those requests still beat direct fitting here. The low-hit mixed parent trace did not benefit. Choose the cache boundary using the full request cost and application hit rate, not the measurement count alone.

## Evidence and limits

The run passed all 36 workload/scenario validations and 17 component rows. The runner verified that measured sources did not change and removed its owned Simulator afterward. The raw export preserves every duration and count; it replaces only the local Simulator instance name. Its attachment digest identifies the original attachment before that replacement. The candidate was the working tree based on `4f4022fda1e18b2d82a20a6494a1384943f64a26`; recorded source fingerprints identify the measured files, not that base commit alone.

The benchmark ran separately from this package's other builds and tests. This is one Simulator batch, not a controlled device study; scheduling and UIKit behavior contribute to variability. No allocation profiler was attached, and cache entry counts do not measure memory. The [synthetic diagnostics](Synthetic.md) remain useful for key/storage regressions, but these UIKit comparisons are the evidence for sizing behavior.
