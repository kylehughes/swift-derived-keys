# Specialization and class-box snapshot results

On 2026-11-09, the working tree was compared against its base commit (`cfce442`) on the same machine. The change set marked the core's hot generic paths `@inlinable`, replaced `AnyHashable` leaf erasure in `DependencySnapshot` with a private class box, merged `DerivedKeysUIKit` into `DerivedKeysUI`, and removed several unused APIs. **Small-payload synthetic lookups ran 1.2 to 5.7 times faster (except typed hashing, which did not change). A warm UIKit label lookup became about 42–47% cheaper, and a warm button lookup went from slower than direct fitting to slightly faster. Most large-payload cases did not change.** Many Simulator rows were too noisy to compare across builds, as the repeated runs below show.

- **Synthetic, 16-byte payloads:** warm hit dropped from 1.21 to 0.22 µs, irrelevant change from 0.74 to 0.13 µs, warm composed parent from 6.69 to 3.86 µs, and cold composed request from 24.54 to 12.27 µs. Hashing a preconstructed typed key was 1.032× (ranges overlap).
- **Synthetic, 4,096-byte payloads:** warm hit and irrelevant change took about a third of the baseline time (0.35×). The composed size cases changed by 0.971× to 1.004×, and two of the three ranges overlap, showing little or no change because payload hashing dominates (typed hashing takes about 14 µs in both builds). Typed hashing was 1.024× with overlapping ranges, which could be a small slowdown or noise.
- **UIKit Simulator, two runs per tree:** the cached warm single-line label lookup fell from 4.06–4.10 to 2.15–2.32 µs, while direct fitting stayed at 0.11–0.12 µs, so a warmed label is **still much faster uncached**. The cached warm button fell from 6.69 and 6.95 µs (slower than its 5.54 and 5.75 µs direct fit in 17 of 18 trials) to 5.52 and 5.32 µs (faster than direct in 8 and 9 of 9 trials). The warm document parent hit did not change measurably (32.20 and 36.85 µs before; 38.70 and 29.08 µs after). The text view is dominated by hashing its text and is too noisy to compare.
- **Mixed document-parent traces did not benefit** from caching in any undisturbed run (cached/direct 1.023× to 1.040×).

**Only a Simulator was used; no physical-device timings were collected, and allocations were not measured.** The UIKit runs were executed sequentially in the order baseline, candidate, candidate, baseline, rather than interleaved; the synthetic trials were interleaved. Raw observations and source fingerprints are stored in the [synthetic measurements](Measurements/Specialization-2026-11-09.json) and the four UIKit exports: [baseline run 1](Measurements/UIKit-Specialization-2026-11-09-Baseline-Run1-Simulator.json), [baseline run 2](Measurements/UIKit-Specialization-2026-11-09-Baseline-Run2-Simulator.json), [candidate run 1](Measurements/UIKit-Specialization-2026-11-09-Candidate-Run1-Simulator.json), and [candidate run 2](Measurements/UIKit-Specialization-2026-11-09-Candidate-Run2-Simulator.json).

## What changed

Between `cfce442` and the candidate working tree, four measurement-relevant changes were made:

- `DependencySnapshot` boxes each leaf value in a private generic class instead of `AnyHashable`, preserving the stored value's concrete hashing and equality.
- The core's generic key, projection, request, and cache paths are marked `@inlinable`.
- `DerivedKeysUIKit` was merged into `DerivedKeysUI`; `KeyValueProvider`, `SizeDependencies.at(_:)`, `LayoutCache`'s `version`, and `@Sendable` requirements were removed; and `+infinity` proposal axes are treated as unconstrained.
- `SizeCache` added a declared-children check in debug builds only; its bookkeeping is compiled out of the Release builds measured here.

The synthetic size benchmark source also changed to match the updated API: the baseline declared children with `at(_:)` and looked up child sizes by child input, whereas the candidate uses `bound(to:)` and looks up child sizes through bindings from the parent input. The `size-*` ratios below therefore reflect both the API change and the core changes. The `warm-hit`, `irrelevant-change`, `typed-hash`, and `shared-source` benchmark sources did not change.

## Synthetic paired trials

Values are **median [minimum–maximum] microseconds per operation** across five trials, with each trial run in a fresh process. Ratios divide the candidate median by the baseline median (lower is faster). Cache capacity is 128. Baseline and candidate order alternates across trials (baseline first in trials 1, 3, and 5). The `shared-source` case reports three phases per run, all included below.

### 16-byte payloads, 200,000 operations per trial

| Diagnostic | Baseline, µs/op | Candidate, µs/op | Candidate / baseline |
| --- | ---: | ---: | ---: |
| Warm hit | 1.21 [1.17–1.26] | 0.22 [0.22–0.23] | 0.183× |
| Irrelevant change | 0.74 [0.73–0.74] | 0.13 [0.13–0.13] | 0.174× |
| Typed hash | 0.12 [0.11–0.12] | 0.12 [0.12–0.12] | 1.032× |
| Size: snapshot capture | 4.07 [4.03–4.10] | 2.98 [2.94–3.13] | 0.733× |
| Size: warm parent | 6.69 [6.54–7.87] | 3.86 [3.65–4.57] | 0.577× |
| Size: parent miss | 16.22 [15.67–17.84] | 8.86 [8.80–9.53] | 0.547× |
| Size: cold composed | 24.54 [24.40–25.15] | 12.27 [12.25–12.71] | 0.500× |
| Shared source: snapshot hashing | 0.60 [0.59–0.61] | 0.44 [0.43–0.48] | 0.741× |
| Shared source: snapshot capture | 1.90 [1.84–1.99] | 1.61 [1.60–1.69] | 0.849× |
| Shared source: warm lookup | 3.45 [3.38–3.49] | 2.12 [2.11–2.19] | 0.614× |

### 4,096-byte payloads, 1,000 operations per trial

| Diagnostic | Baseline, µs/op | Candidate, µs/op | Candidate / baseline |
| --- | ---: | ---: | ---: |
| Warm hit | 38.67 [38.52–39.02] | 13.67 [13.63–13.97] | 0.354× |
| Irrelevant change | 38.66 [38.53–39.50] | 13.81 [13.42–14.23] | 0.357× |
| Typed hash | 14.30 [13.66–14.43] | 14.64 [14.05–15.35] | 1.024× |
| Size: snapshot capture | 4.46 [4.36–5.01] | 3.24 [3.11–3.43] | 0.726× |
| Size: warm parent | 81.80 [81.23–83.26] | 79.62 [78.61–80.50] | 0.973× |
| Size: parent miss | 486.83 [486.21–507.81] | 488.63 [459.68–502.59] | 1.004× |
| Size: cold composed | 883.25 [850.79–944.90] | 858.01 [841.21–869.34] | 0.971× |
| Shared source: snapshot hashing | 76.25 [76.14–77.11] | 75.69 [75.45–82.56] | 0.993× |
| Shared source: snapshot capture | 1.99 [1.92–2.06] | 1.68 [1.58–1.74] | 0.845× |
| Shared source: warm lookup | 79.68 [79.11–80.29] | 77.80 [77.40–78.02] | 0.976× |

At 4,096 bytes, typed hashing alone costs about 14 µs in both builds, and payload hashing dominates the composed size cases (shared-source hashing is about 76 µs), so those rows barely moved. By contrast, single-payload `warm-hit` and `irrelevant-change` fell from about 39 µs to 14 µs—close to the 14 µs typed-hash cost—showing that most of the baseline's extra overhead in those two cases was outside payload hashing. Because the changes were tested together, these numbers do not isolate which specific change produced the drop.

Snapshot capture is faster at both payload sizes. At 4,096 bytes, the `size-warm-parent` and `shared-source` warm-lookup medians differ by 2–3% (small even where min–max ranges do not overlap), and the `size-parent-miss` and `size-cold` ranges overlap; treat all four as showing little or no change.

Cache calculation counts matched across both builds: `size-warm-parent` ran 0 / 0 / 0 calculations after one warmup per cache, and `size-parent-miss` and `size-cold` ran 200,000 calculations at the same levels in both builds. Per-run checksums for hash-valued cases differ between processes because Swift randomly seeds `Hasher` per process, so checksums are not comparable across runs.

## UIKit Simulator runs

Each UIKit run executes nine trials of 128 requests per arm. The baseline runs used a clean detached worktree at `cfce442` with its own runner and test target; the candidate runs used the working tree. Runs executed back-to-back in the order baseline run 1, candidate run 1, candidate run 2, baseline run 2. Because the direct arm calls only UIKit, any difference in the direct column between two runs of the same tree is environmental noise, and any difference in the direct column between baseline and candidate is not caused by the library.

### Headline rows

Cells show **direct / cached median µs per request**, followed by the number of trials (out of 9) in which the cached arm was faster.

| Row | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm single-line label | 0.12 / 4.10 (0/9) | 0.11 / 4.06 (0/9) | 0.11 / 2.15 (0/9) | 0.12 / 2.32 (0/9) |
| Warm document button | 5.54 / 6.69 (0/9) | 5.75 / 6.95 (1/9) | 5.72 / 5.52 (8/9) | 5.58 / 5.32 (9/9) |
| Warm text view | 3,103.12 / 540.90 (9/9) | 3,492.53 / 260.47 (9/9) | 1,634.14 / 163.33 (9/9) | 3,222.12 / 696.04 (9/9) |
| Warm document parent | 283.01 / 32.20 (9/9) | 403.53 / 36.85 (9/9) | 380.86 / 38.70 (9/9) | 319.97 / 29.08 (9/9) |
| Parent-only spacing miss | 291.23 / 83.93 (9/9) | 996.10 / 132.52 (9/9) | 288.65 / 73.38 (9/9) | 289.17 / 74.56 (9/9) |
| Mixed document parent | 2,219.12 / 2,308.73 (2/9) | 2,302.28 / 2,380.64 (0/9) | 2,148.18 / 2,197.39 (2/9) | 3,863.31 / 3,657.27 (5/9) |

- **Warm label:** cached lookup dropped from 4.06–4.10 µs in the baseline to 2.15–2.32 µs in the candidate across both runs of each tree. Direct fitting stayed at 0.11–0.12 µs throughout, so caching a warm label is still slower than fitting it directly. Multiline and attributed labels show the same pattern (cached 2.21–2.47 µs in the candidate versus 3.89–4.85 µs in the baseline).
- **Warm button:** the cached/direct ratio shifted from 1.208× and 1.210× in the baseline to 0.966× and 0.955× in the candidate. The button's equivalent-view pool rows shifted similarly. On the width-changes row, the candidate tied the direct arm in run 1 (1.000×, faster in 3 of 9 trials) and was slightly faster in run 2 (0.978×, 9 of 9).
- **Warm document parent:** the two baseline runs measured 32.20 and 36.85 µs, and the two candidate runs measured 38.70 and 29.08 µs. Because the spread within each tree is as wide as the difference between trees, these runs do not show a measurable change on the parent hit. The document text child alone was slightly faster in the candidate (about 22.9–23.4 versus 21.7 µs, a 5–7% drop across all four runs).
- **Spacing-only parent miss:** the candidate measured 73.38 and 74.56 µs against the baseline's 83.93 and 132.52 µs. Because baseline run 2 was disturbed (its direct arm spiked to 996 µs versus 291 µs in run 1), the supported comparison is an 11–13% reduction relative to baseline run 1.
- **Text view:** across the four runs, the cached warm lookup ranged from 163 to 696 µs and the direct arm from 1,634 to 3,492 µs, which is too noisy to compare builds. The isolated component diagnostics below show that hashing the text view's string stayed constant at roughly 61–65 µs.
- **Mixed document parent:** the cached arm was slower than direct fitting in all three undisturbed runs (cached/direct ratios of 1.040×, 1.034×, and 1.023×, with the cached arm faster in 2, 0, and 2 of 9 trials). Candidate run 2 was disturbed, with both arms spiking to roughly 3,700–3,900 µs.

### Component diagnostics

Each phase ran five trials of 512 operations on a stable warmed fixture; values are median µs per operation. Phases include their own observation sinks and are not additive. Min–max ranges are in the raw JSON exports.

| Workload | Phase | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | --- | ---: | ---: | ---: | ---: |
| UILabel-single-line | Warm UIKit fit | 0.080 | 0.077 | 0.086 | 0.078 |
| UILabel-single-line | Dependency capture | 2.150 | 2.136 | 1.572 | 1.690 |
| UILabel-single-line | Preconstructed snapshot hash | 0.331 | 0.331 | 0.130 | 0.134 |
| UILabel-single-line | Full warm lookup | 3.776 | 3.965 | 2.023 | 2.105 |
| UILabel-multiline | Warm UIKit fit | 0.080 | 0.075 | 0.086 | 0.075 |
| UILabel-multiline | Dependency capture | 2.151 | 2.200 | 1.570 | 1.622 |
| UILabel-multiline | Preconstructed snapshot hash | 0.497 | 0.482 | 0.310 | 0.323 |
| UILabel-multiline | Full warm lookup | 3.960 | 3.896 | 2.211 | 2.262 |
| UILabel-attributed | Warm UIKit fit | 0.079 | 0.075 | 0.084 | 0.077 |
| UILabel-attributed | Dependency capture | 2.119 | 2.161 | 1.567 | 1.670 |
| UILabel-attributed | Preconstructed snapshot hash | 0.350 | 0.359 | 0.161 | 0.177 |
| UILabel-attributed | Full warm lookup | 3.744 | 3.840 | 2.057 | 2.203 |
| UITextView | Warm UIKit fit | 874.876 | 902.969 | 828.264 | 1,357.378 |
| UITextView | Dependency capture | 1.568 | 1.538 | 1.143 | 1.287 |
| UITextView | Preconstructed snapshot hash | 62.708 | 61.864 | 61.122 | 64.562 |
| UITextView | Full warm lookup | 152.813 | 152.854 | 146.623 | 178.137 |
| UITextView | Text getter | 0.341 | 0.335 | 0.311 | 0.343 |

Across the three label workloads, full warm lookups dropped by about 42–47% when comparing runs in order (run 1 against run 1, run 2 against run 2): single-line fell from 3.78 to 2.02 µs and from 3.97 to 2.11 µs; multiline from 3.96 to 2.21 µs and from 3.90 to 2.26 µs; attributed from 3.74 to 2.06 µs and from 3.84 to 2.20 µs. Preconstructed snapshot hashing fell by about 33–62%. On `UITextView`, hashing the text dominates (about 61–65 µs) and did not change, while both warm UIKit fitting and full warm lookup varied across runs (for example, full warm lookup was 146.6 and 178.1 µs across the two candidate runs).

### Paired measurements

Cells show direct / cached median µs per request, followed by the number of trials (out of 9) in which the cached arm was faster. Min–max ranges for every cell are in the raw JSON exports. Untimed replay hit counts, miss counts, and cache entry counts were identical across all four runs for all 36 workload-and-scenario rows, confirming that timing differences do not stem from different cache hit behavior.

#### UILabel-single-line

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.12 / 4.10 (0/9) | 0.11 / 4.06 (0/9) | 0.11 / 2.15 (0/9) | 0.12 / 2.32 (0/9) |
| Equivalent view pool | 1.38 / 4.03 (0/9) | 1.32 / 4.06 (0/9) | 1.34 / 2.17 (1/9) | 1.39 / 2.31 (0/9) |
| Width changes | 0.12 / 4.31 (0/9) | 0.12 / 4.34 (0/9) | 0.12 / 2.38 (0/9) | 0.12 / 2.37 (0/9) |
| Content/font changes | 1,611.94 / 31.43 (9/9) | 852.83 / 29.09 (8/9) | 742.94 / 25.48 (9/9) | 583.10 / 25.71 (9/9) |
| Mixed, capacity 16 | 1,443.25 / 573.24 (6/9) | 250.40 / 1,151.44 (3/9) | 735.55 / 1,207.12 (3/9) | 322.05 / 384.61 (3/9) |

#### UILabel-multiline

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 / 4.12 (0/9) | 0.12 / 4.85 (0/9) | 0.12 / 2.47 (1/9) | 0.11 / 2.33 (0/9) |
| Equivalent view pool | 13.02 / 4.14 (9/9) | 14.12 / 4.45 (7/9) | 14.36 / 2.41 (9/9) | 13.17 / 2.37 (9/9) |
| Width changes | 0.65 / 4.96 (0/9) | 0.59 / 4.94 (0/9) | 0.60 / 3.04 (0/9) | 0.60 / 3.02 (0/9) |
| Content/font changes | 5,948.90 / 193.05 (9/9) | 976.16 / 78.01 (9/9) | 1,167.88 / 111.18 (9/9) | 686.06 / 49.21 (9/9) |
| Mixed, capacity 16 | 4,635.94 / 4,180.78 (5/9) | 396.87 / 426.27 (1/9) | 382.34 / 427.08 (5/9) | 391.11 / 393.67 (1/9) |

#### UILabel-attributed

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 0.11 / 3.89 (0/9) | 0.11 / 4.00 (0/9) | 0.11 / 2.21 (0/9) | 0.12 / 2.30 (0/9) |
| Equivalent view pool | 13.13 / 3.95 (9/9) | 13.22 / 4.11 (9/9) | 12.98 / 2.24 (9/9) | 13.37 / 2.29 (9/9) |
| Width changes | 0.64 / 5.57 (0/9) | 0.65 / 4.79 (0/9) | 0.62 / 2.81 (0/9) | 0.63 / 2.85 (0/9) |
| Content/font changes | 2,049.88 / 186.62 (9/9) | 531.06 / 79.30 (9/9) | 5,046.24 / 923.76 (9/9) | 399.66 / 59.72 (9/9) |
| Mixed, capacity 16 | 3,950.21 / 2,097.19 (7/9) | 2,743.97 / 3,103.27 (6/9) | 1,766.96 / 1,089.95 (5/9) | 368.27 / 316.02 (9/9) |

#### UITextView

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 3,103.12 / 540.90 (9/9) | 3,492.53 / 260.47 (9/9) | 1,634.14 / 163.33 (9/9) | 3,222.12 / 696.04 (9/9) |
| Equivalent view pool | 1,300.50 / 205.67 (9/9) | 1,605.39 / 201.83 (9/9) | 2,533.34 / 226.90 (9/9) | 2,688.44 / 757.08 (9/9) |
| Width changes | 1,116.98 / 177.33 (9/9) | 1,076.33 / 235.89 (9/9) | 1,124.27 / 264.68 (9/9) | 2,114.41 / 417.13 (9/9) |
| Content/font changes | 2,672.99 / 2,226.09 (9/9) | 2,826.69 / 2,284.36 (7/9) | 2,653.28 / 2,136.40 (9/9) | 4,815.72 / 3,151.53 (8/9) |
| Mixed, capacity 16 | 2,016.71 / 2,219.54 (2/9) | 2,344.87 / 2,022.20 (5/9) | 2,070.90 / 2,175.04 (3/9) | 2,147.91 / 2,217.12 (3/9) |

#### DocumentContentView-text

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 269.76 / 23.40 (9/9) | 255.87 / 22.89 (9/9) | 262.49 / 21.74 (9/9) | 270.98 / 21.70 (9/9) |
| Equivalent view pool | 296.28 / 23.05 (9/9) | 265.50 / 23.43 (9/9) | 256.06 / 21.18 (9/9) | 371.72 / 21.77 (9/9) |
| Width changes | 315.69 / 30.96 (9/9) | 291.66 / 26.93 (9/9) | 241.88 / 23.15 (9/9) | 264.57 / 24.13 (9/9) |
| Content/font changes | 2,940.33 / 2,053.90 (9/9) | 2,883.67 / 1,994.19 (9/9) | 3,110.74 / 2,143.65 (9/9) | 3,111.77 / 2,095.93 (9/9) |
| Mixed, capacity 16 | 2,224.85 / 2,209.77 (5/9) | 2,264.90 / 2,352.98 (3/9) | 2,206.05 / 2,164.24 (8/9) | 2,201.88 / 2,187.29 (5/9) |

#### DocumentContentView-button

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm unchanged view | 5.54 / 6.69 (0/9) | 5.75 / 6.95 (1/9) | 5.72 / 5.52 (8/9) | 5.58 / 5.32 (9/9) |
| Equivalent view pool | 5.72 / 6.84 (0/9) | 5.72 / 6.92 (0/9) | 5.78 / 5.67 (9/9) | 5.63 / 5.43 (9/9) |
| Width changes | 5.58 / 7.07 (0/9) | 5.61 / 7.27 (0/9) | 5.67 / 5.66 (3/9) | 5.61 / 5.48 (9/9) |
| Content/font changes | 3,147.32 / 2,569.96 (6/9) | 2,075.03 / 1,896.28 (5/9) | 3,386.75 / 4,030.39 (6/9) | 1,821.03 / 1,808.66 (5/9) |
| Mixed, capacity 16 | 1,971.64 / 2,095.13 (4/9) | 1,428.82 / 1,433.66 (4/9) | 1,676.99 / 1,688.64 (5/9) | 1,498.92 / 1,525.93 (3/9) |

#### DocumentContentView-parent

Cells are direct / cached median µs per request, with cached-faster trials of 9.

| Scenario | Baseline run 1 | Baseline run 2 | Candidate run 1 | Candidate run 2 |
| --- | ---: | ---: | ---: | ---: |
| Warm parent | 283.01 / 32.20 (9/9) | 403.53 / 36.85 (9/9) | 380.86 / 38.70 (9/9) | 319.97 / 29.08 (9/9) |
| Equivalent view pool | 288.63 / 32.81 (9/9) | 307.79 / 36.49 (9/9) | 308.22 / 30.54 (9/9) | 301.45 / 29.81 (9/9) |
| Parent-only spacing | 291.23 / 83.93 (9/9) | 996.10 / 132.52 (9/9) | 288.65 / 73.38 (9/9) | 289.17 / 74.56 (9/9) |
| Width changes | 293.08 / 35.37 (9/9) | 794.24 / 61.27 (9/9) | 295.45 / 32.09 (9/9) | 293.24 / 32.74 (9/9) |
| Content/font changes | 2,650.92 / 1,957.79 (9/9) | 2,915.35 / 2,153.44 (9/9) | 2,489.90 / 1,831.10 (9/9) | 2,539.92 / 1,871.30 (9/9) |
| Mixed, capacity 16 | 2,219.12 / 2,308.73 (2/9) | 2,302.28 / 2,380.64 (0/9) | 2,148.18 / 2,197.39 (2/9) | 3,863.31 / 3,657.27 (5/9) |

### Noisy rows

The repeated runs identify which rows suffered from Simulator noise. Within the same tree, the direct arm on these rows varied across runs by large factors:

- UILabel-multiline, content/font changes: baseline direct 5,948.90 versus 976.16 µs.
- UILabel-attributed, content/font changes: candidate direct 5,046.24 versus 399.66 µs.
- UILabel-single-line, mixed: baseline direct 1,443.25 versus 250.40 µs.
- UILabel-attributed, mixed: candidate direct 1,766.96 versus 368.27 µs.
- DocumentContentView-parent, spacing-only: baseline direct 291.23 versus 996.10 µs.
- UITextView (several rows): for example, warm direct ranged from 1,634.14 to 3,492.53 µs across the four runs.

Do not draw build-to-build conclusions from the content/font, mixed, or `UITextView` rows. The conclusions at the top of this report rest on the warm, equivalent-view pool, and width-change rows for `UILabel`, `DocumentContentView-button`, and `DocumentContentView-text`, which stayed consistent across both runs of each tree.

## Environment

| Setting | Value |
| --- | --- |
| Host | Apple M1 Max, MacBookPro18,2; 10 logical CPUs; 64 GiB; macOS 27.2 (26B123), arm64 |
| Toolchain | Xcode 27.1 (27A9275); Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`) |
| Synthetic build | SwiftPM Release, Swift 6 mode, tools 6.4, macOS 13 package minimum; macOS binary |
| UIKit build | Release, Swift 6 mode, iOS Simulator 27.1 SDK; iOS 16 minimum; coverage and parallel testing off |
| UIKit destination | iPhone Duo Simulator (owned, created and deleted by the runner for each run), arm64; iOS 27.1 (24A94425) |
| UIKit sampling | Nine paired trials of 128 requests per arm; capacity 16 per cache; diagnostics use five trials of 512 operations |
| Baseline | `cfce44255e4030a3f5462811e92e8f2bd4aa0fa3`, clean detached worktree |
| Candidate | The uncommitted working tree on that commit; tracked-diff SHA-256 `c782325d6946e2e4088936683a566a1a1e877b8c67b6cf1f204a0c52d4a637b4`. Untracked new source files are covered by the source fingerprints in the exports |
| UIKit run times (UTC) | Baseline run 1 21:26:48–21:31:35; candidate run 1 21:31:35–21:35:49; candidate run 2 21:35:49–21:40:18; baseline run 2 21:40:18–21:44:39 |

Because the Simulator runtime and device model here (iPhone Duo, iOS 27.1) differ from the [2026-10-30 report](UIKit-Native-Fitting-Results.md) (iPhone 18 Pro, iOS 27.0), absolute timings are not directly comparable across the two reports.

## What was and was not measured

- **Measured:** five interleaved synthetic trials per case across two payload sizes, plus two sequential UIKit Simulator runs per tree.
- **Not measured:** physical devices, heap allocations, memory usage, cache storage footprint, the debug-only declared-children check (compiled out in Release), and the `strings` benchmark suite.
- **Run ordering and spread:** the four UIKit runs executed sequentially in the order baseline, candidate, candidate, baseline, which partially balances slow machine-state drift over the 18-minute window without eliminating it. Two runs per tree expose run-to-run spread, not statistical confidence intervals.
- **Controls:** min–max ranges are not confidence intervals, and timer overhead is not subtracted. Background processes and thermal/power state were not isolated, though no other builds ran during timing.
- **Synthetic size API difference:** as noted under [What changed](#what-changed), the `size-*` synthetic cases also reflect the move from `at(_:)` to `bound(to:)`.
- **Verification and provenance:** on each UIKit run, the runner verified that one XCTest case ran, all 36 workload-and-scenario rows and 17 component rows completed with matching checksums, tracked sources did not change during the run, and the temporary Simulator was deleted. The committed JSON exports redact only the ephemeral Simulator name (`attachmentSHA256` records the unmodified XCTest attachment digest). The synthetic JSON export records SHA-256 digests for all source files in both trees and for both compiled benchmark binaries.
- **Later comment edits:** after these runs, documentation comments in 17 files under `Sources/DerivedKeys` and `Sources/DerivedKeysUI` were reworded. No line of code changed, so the measured binaries are unaffected, but the recorded SHA-256 fingerprints for those files describe the pre-edit comments.

## Reproduce

Create a baseline checkout outside the repository and build both trees:

```sh
git worktree add --detach "$BASELINE" HEAD
(cd "$BASELINE" && swift build -c release --product DerivedKeysBenchmarks)
swift build -c release --product DerivedKeysBenchmarks
```

Run each executable with the same arguments, alternating order over five trials, for the cases `warm-hit`, `irrelevant-change`, `typed-hash`, `size-snapshot`, `size-warm-parent`, `size-parent-miss`, `size-cold`, and `shared-source`:

```sh
DerivedKeysBenchmarks --case warm-hit --iterations 200000 --payload-bytes 16 --capacity 128
DerivedKeysBenchmarks --case warm-hit --iterations 1000 --payload-bytes 4096 --capacity 128
```

Run the UIKit sizing suite in the order baseline, candidate, candidate, baseline, one after the other, each with a fresh output directory:

```sh
(cd "$BASELINE" && python3 Benchmarks/run-uikit.py --output "$BASELINE_OUTPUT_1")
python3 Benchmarks/run-uikit.py --output "$CANDIDATE_OUTPUT_1"
python3 Benchmarks/run-uikit.py --output "$CANDIDATE_OUTPUT_2"
(cd "$BASELINE" && python3 Benchmarks/run-uikit.py --output "$BASELINE_OUTPUT_2")
```

Remove the baseline with `git worktree remove "$BASELINE"` when finished. See the [synthetic methodology](Synthetic.md) and the [UIKit benchmark guide](README.md) for loop boundaries, warmup, and validation.
