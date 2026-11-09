# UIKit sizing benchmarks

These benchmarks compare direct UIKit fitting (`sizeThatFits(_:)`) against `DerivedKeysUI.SizeCache`, preserving UIKit's own warmed measurement behavior in the direct baseline. Pick the report that matches your question:

- [Native fitting and composition](UIKit-Native-Fitting-Results.md): Simulator timings for the current document example. Start here when evaluating `SizeCache` for an app.
- [Specialization and class-box snapshots](Specialization-Results.md): Paired synthetic trials and two sequential Simulator runs comparing `@inlinable` specialization and class-box leaf snapshots against the prior commit.
- [UIKit versus model strings](String-Results.md): Simulator breakdown of `UITextView.text` versus native Swift model `String` lookup costs.
- [Earlier recipe-based run](UIKit-Results.md): Historical sizing measurements from the earlier recipe-based example.
- [Synthetic diagnostics](Synthetic.md): Key construction, hashing, and cache lookup costs isolated from UIKit fitting.

Every cache lookup still reads the selected key paths and hashes and compares the resulting snapshot. Caching pays off only when that lookup work costs less than the measurement it skips, often enough to outweigh misses and evictions. Fewer measurement calls alone do not prove a speedup.

## Run on a device or Simulator

Select Xcode 27.1 (Swift 6.4). When invoked with no `--destination`, the runner creates a fresh iOS Simulator, runs the benchmark, and deletes only that Simulator afterward:

```sh
python3 Benchmarks/run-uikit.py
```

If you pass an existing Simulator via `--destination`, the runner leaves it intact. In both cases, the script builds the package in **Release** with code coverage and parallel testing disabled, then runs the benchmark XCTest case in `DerivedKeysUIExampleTests` without adding an app target or external dependency. During normal `swift test` or `xcodebuild test` runs outside the benchmark script, that test case executes a short correctness trace instead of skipping.

The runner accepts physical-device destinations and local signing arguments (without enabling provisioning updates), and a connected-device build succeeded under Xcode 27.1. However, Xcode 27.1 rejected running the test on hardware because the package uses tool-hosted tests, which require a host application target not present in this repository; no physical-device timings were collected.

The default `sizing` suite runs 128 requests per timed loop across 9 paired trials per workload, with each cache fixed at capacity 16 regardless of iteration count. You can customize a sizing run with `--iterations` (48–512), `--trials` (3–30), and `--output` (a new directory path; keep generated output outside tracked source).

To run the string-representation comparison instead:

```sh
python3 Benchmarks/run-uikit.py --suite strings
```

The `strings` suite fixes 128 requests, 9 trials, and capacity 16. It compares direct fitting, `UITextView.text` key-path reads, authoritative model `String` properties, and per-request `makeContiguousUTF8()` conversion across repeated requests, A-B-A mutations, and a bounded mixed trace. See [String-Results.md](String-Results.md) for the phase boundaries and results.

Each run writes the raw `.xcresult` bundle, extracted JSON attachment, exact commands, toolchain and destination metadata, source SHA-256 fingerprints, and a summary receipt. The runner exits with an error if any test is missing, direct and cached outputs disagree, observations are incomplete, or tracked source files change during the run. To run the runner's parser unit tests:

```sh
python3 Benchmarks/test-run-uikit.py
```

## What is measured

All workloads in the default `sizing` suite run synchronously on the main actor against real UIKit views and the [`DocumentContentView`](../Sources/DerivedKeysUIExample/DocumentContentView.swift) example. Composed-document timings measure child sizing and final size combination; frame assignment, drawing, and scrolling are outside the harness.

| Workload | Selected values and configuration |
| --- | --- |
| Single-line and multiline `UILabel` | Ordinary `text`, `font`, `numberOfLines`, and `lineBreakMode` key paths; fixed left-to-right direction. |
| Attributed `UILabel` | Immutable `attributedText`, `font`, line count, and line-break mode; bold opening text, line spacing, and kerning. |
| `UITextView` | Ordinary text and font dependencies; scrolling, editing, and selection disabled; fixed text-container insets and padding. |
| Document text and button | The actual `DocumentSizeCaches.textSizes` and `buttonSizes` handles, selecting text, font, and maximum line count for the text view, and current title and title font for the button. |
| Composed document | The actual parent cache, with the same child handles, proposal transformation, and combination used by the application example. |

Test inputs cover a short title, a multiline paragraph, long body text, and attributed text:

- Standalone controls test 17-, 24-, and 32-point fonts; document views use the example's body font across `.large`, `.accessibilityMedium`, and `.accessibilityExtraExtraExtraLarge` content-size categories.
- Outer fitting widths are 180 and 320 points with unconstrained height; `DocumentContentView` subtracts its fixed 12-point horizontal padding on each side before measuring children.
- All unselected view settings stay constant for the recipe's lifetime. `DocumentContentView` updates its subviews eagerly on initialization and on model or trait changes, so property getters only read existing control state.
- Strings, fonts, immutable `NSAttributedString` instances, request schedules, views, and output buffers are allocated before timing starts. The mixed trace cycles through 40 prebuilt semantic variants using ordinary UIKit key paths—no custom dependency wrappers or aggregate input structs.

### Scenarios and timing boundaries

| Scenario | Comparison |
| --- | --- |
| Warm unchanged view | Repeated fitting of one already-configured, warmed control versus a warmed size-cache entry. |
| Equivalent view instances | Eight preconfigured, initially unfitted request views share equivalent inputs; a separate ninth seed warms UIKit and the cache. The request views are then reused throughout the loop. |
| Warm composed parent | Direct child fitting and combination versus a parent hit that skips the layout calculation. |
| Parent-only spacing change | Each request changes spacing, producing a parent miss while preserving the children's inputs and proposals. |
| Width changes | Alternate the outer width, including the document parent's transformed inner width. Earlier widths may reuse retained results. |
| Content or typography changes | Assign prepared content and font/category values before fitting, exercising relevant misses and subsequent reuse. |
| Mixed bounded requests | A 48-request cycle contains adjacent repeats and new semantic inputs, with capacity 16. Content-dependent caches evict; the fixed-title document button's six width/category combinations fit without eviction. |

- **Measurement-only scenarios (warm unchanged view, equivalent view instances, warm composed parent):** Views are configured before the timed loop. In the direct arm, `DocumentContentView` keeps its configured subviews and calls `sizeThatFits(_:)` without reassigning properties inside the loop, preserving UIKit's internal layout caches.
- **Input-changing scenarios (content/typography changes, mixed bounded requests):** Both arms include the same property assignments inside the timed loop. For `DocumentContentView`, content/font and mixed rows update the entire view (including text assignment and content-size category propagation) even when timing the button child cache alone.
- **Proposal- and spacing-only scenarios (width changes, parent-only spacing change):** Only the fitting proposal or parent `spacing` property changes inside the loop; neither triggers subview reconfiguration. On a parent-only spacing change, the direct arm still accesses and fits the unchanged children, while the cached parent misses and hits its warm child caches.

Each trial builds separate direct and cached fixture instances and alternates which arm runs first. Warmup primes the cache entry before performing four final direct `sizeThatFits(_:)` warmup calls per warmed view (equivalent-view rows warm only the ninth seed view) so cache setup never invalidates UIKit's warm state in the direct baseline. Timed loops write sizes into preallocated buffers without subtracting loop or clock overhead; equality checks, diagnostics, and JSON serialization run after timing finishes.

### Results and cache observations

Every timed pair of direct and cached `CGSize` results is verified after timing to be equal, finite, and positive in height. Reports include raw per-trial times, checksums, medians, min–max ranges, microseconds per request, and cached-to-direct ratios. Always evaluate wall-clock times rather than measurement call counts.

To verify cache behavior without adding counters to timed closures:

- **Standalone controls** run a separate, untimed replay using measurement-closure counters.
- **`DocumentSizeCaches`** runs an untimed prefix replay against fresh caches, using public `count` and `removeSize(of:toFit:)` calls to test whether the next request is already cached. A parent hit performs no child probe; a parent miss probes the child caches with their transformed proposals. Because each prefix runs in its own fresh cache, probing via `removeSize(of:toFit:)` never alters subsequent requests.

In the exported JSON, document hit/miss counts are direct membership observations, whereas document measurement counts are **inferred from misses** (distinct from standalone closure counters). Untimed assertions verify capacity bounds, warm hits, parent-only child hits, and that mixed traces produce both hits and misses (plus eviction on content-dependent caches).

The UIKit harness does not attach an allocation profiler or measure heap bytes; cache `count` is an entry count, not a memory measurement. Report Simulator and physical-device timings separately—Simulator numbers do not predict hardware performance.

### Investigating lookup cost

Alongside the paired end-to-end runs, the XCTest fixture runs five isolated component phases on a warmed fixture (5 trials of 512 operations each, in fixed order):

1. Warm UIKit `sizeThatFits(_:)`.
2. Dependency snapshot capture.
3. Hashing a preconstructed `DependencySnapshot`.
4. Full warm `SizeCache` lookup.
5. Reading `UITextView.text` (`UITextView` workload only).

Each phase includes its own observation sink (64 rotating slots for snapshots and strings, a preallocated buffer for sizes, and an integer accumulator for hashes), so you cannot subtract one phase from another to isolate equality or LRU bookkeeping. Use these component phases to spot where lookup time is spent before inspecting end-to-end workloads.

## Choosing dependencies for an application

Start by selecting ordinary, stable properties directly. `DependencySnapshot` boxes each selected leaf value in a private generic class that preserves its concrete `Hashable` implementation without `AnyHashable`, so you do not need custom wrapper structs around arrays or strings to avoid element-by-element erasure.

When a model already holds the authoritative text, select the model's `String` key path (such as `\.model.text`) and keep the rendered view synchronized. In the [Simulator string comparison](String-Results.md), hashing a long ASCII string read back from `UITextView.text` took 62.98 µs (149.75 µs for a full warm lookup) because `UITextView.text` returns an `NSString`-bridged string, whereas hashing the same text from a native Swift model `String` took 1.26 µs (3.56 µs for a full warm lookup). Calling `makeContiguousUTF8()` on the bridged string every request lowered the warm lookup to 36.70 µs (including conversion), which is still much slower than reading the model property directly—and on changing-input workloads, view configuration and text layout dominated both. Note that model strings can also be bridged or noncontiguous; always measure your actual request path rather than normalizing strings blindly. See the [model-text example](../Examples/Size-Caches.md#select-authoritative-model-text) for the synchronization pattern.

If hashing long text remains a measured bottleneck even with native strings, you can project a content ID paired with a revision counter under the [sizing guide's revision contract](../Examples/Size-Caches.md#consider-a-compact-projection-after-measuring), alongside any typography and layout dependencies. Profile your hit rate, text lengths, and direct UIKit fitting cost first: for a small control whose warm `sizeThatFits(_:)` is already sub-microsecond (such as `UILabel`), direct measurement or caching a single last-known size is often faster than a keyed cache lookup. See the [README](../README.md) for the full `SizeCache` API.

## Synthetic diagnostics

Run the standalone macOS release benchmarks for the generic core and `SizeCache` with:

```sh
Benchmarks/run.sh
```

See [Synthetic.md](Synthetic.md) for the synthetic workload definitions, [Erasure-Results.md](Erasure-Results.md) for the earlier `AnyHashable`-removal comparison, and [Specialization-Results.md](Specialization-Results.md) for the `@inlinable` and class-box comparison. Earlier single-run baselines remain in [Results.md](Results.md) and [Size-Results.md](Size-Results.md) under their original toolchains and source revisions.
