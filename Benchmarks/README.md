# UIKit sizing benchmarks

These benchmarks compare direct UIKit fitting with `DerivedKeysUI.SizeCache`, including UIKit's own warmed measurement behavior. Choose a report for the question you want to investigate:

- [Native fitting and composition](UIKit-Native-Fitting-Results.md): Simulator measurements of the current document example. Start here for application sizing.
- [UIKit versus model strings](String-Results.md): a Simulator investigation of text-view lookup costs.
- [Earlier recipe-based run](UIKit-Results.md): historical sizing evidence from the earlier example.
- [Synthetic diagnostics](Synthetic.md): key and storage costs measured separately from UIKit fitting.

A cache hit still reads dependencies and hashes and compares their snapshots. It helps when that work costs less than the measurement it avoids, often enough to cover misses and eviction. Fewer measurement calls alone do not establish a speedup.

## Run on a device or Simulator

Select the package's Xcode 27.1 / Swift 6.4 toolchain. With no destination, the runner creates an iOS Simulator, runs the benchmark, then deletes only that Simulator:

```sh
python3 Benchmarks/run-uikit.py
```

You can also supply an explicit Simulator destination; the runner preserves it. The runner builds the actual package in **Release**, disables code coverage and parallel testing, then runs one XCTest case from `DerivedKeysUIExampleTests`. No app product or dependency is added to the package. Outside a benchmark run, the test exercises a small correctness trace instead of skipping.

The runner accepts physical-device destinations and local signing arguments, but the current package scheme uses tool-hosted tests. Xcode 27.1 rejected device execution because it requires a host application. A connected-device build succeeded; no device timings were collected. Running this fixture on hardware requires an app-hosted test target, which this repository does not currently provide. The runner does not enable provisioning updates.

The default `sizing` suite uses 128 requests per timed loop and nine paired trials per workload. Each cache has capacity 16, independent of those settings. Use `--iterations` (48–512), `--trials` (3–30), and `--output` (a new directory) to select another bounded sizing run. Keep generated evidence outside tracked source.

Run the focused string-representation comparison with:

```sh
python3 Benchmarks/run-uikit.py --suite strings
```

The string suite uses a fixed 128 requests, nine trials, and capacity 16. It compares direct fitting, `UITextView.text` dependencies, authoritative model text, and explicit per-request UTF-8 conversion. It measures repeated requests, mutations with returns to previous content, and a bounded mixed trace. See its [results and timing boundaries](String-Results.md) for component diagnostics and validation.

The output includes the raw XCTest result, JSON attachment, commands, toolchain and destination metadata, candidate source fingerprints, and a receipt. The runner fails if tests are missing, comparisons fail, observations are incomplete, or source files change during execution. Its parser controls are available with:

```sh
python3 Benchmarks/test-run-uikit.py
```

## What is measured

The following workload description covers the default sizing suite. All UIKit work runs synchronously on the main actor. Composed-document timings cover child sizing and final-size combination; frame assignment, drawing, and scrolling are outside this harness. The suite uses actual controls and the current [document example](../Sources/DerivedKeysUIExample/DocumentContentView.swift):

| Workload | Selected values and configuration |
| --- | --- |
| Single-line and multiline `UILabel` | Ordinary `text`, `font`, `numberOfLines`, and `lineBreakMode` key paths; fixed left-to-right direction. |
| Attributed `UILabel` | Immutable `attributedText`, `font`, line count, and line-break mode; bold opening text, line spacing, and kerning. |
| `UITextView` | Ordinary text and font dependencies; scrolling, editing, and selection disabled; fixed text-container insets and padding. |
| Document text and button | The actual `DocumentSizeCaches.textSizes` and `buttonSizes` handles, selecting text, font, and maximum line count for the text view, and current title and title font for the button. |
| Composed document | The actual parent cache, with the same child handles, proposal transformation, and combination used by the application example. |

Inputs include a short title, a multiline paragraph, long text, and attributed content. Standalone controls use 17-, 24-, and 32-point fonts. Document views use the example's body font with large, accessibility-medium, and accessibility-extra-extra-extra-large content-size categories. Outer widths are 180 and 320 points. The document parent subtracts its fixed 12-point padding on each side; child fitting height is unconstrained. All other measurement settings are fixed for the recipe's lifetime. Document controls are configured eagerly at initialization and model or trait changes; getters only read controls.

Prepared strings, standalone fonts, immutable attributed inputs, request traces, view creation, and result-buffer allocation are outside timing. The mixed trace uses 40 prepared semantic variants; callers still use ordinary UIKit key paths, with no custom dependency wrapper or aggregate sizing-input type.

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

Warm and equivalent-view rows are **measurement-only**: controls are configured before timing. Direct document measurements retain the configured controls and call their UIKit fitting methods without reassigning their content in the loop. This preserves UIKit's own warm behavior.

Changing rows include the applicable configuration work in both arms. Content/font changes assign the same prepared values, eagerly synchronizing document controls in both arms. Document content/font and mixed rows configure the whole document, even when measuring only its button; those rows include text assignment and category propagation, not just button work.

Width changes update only proposals, and spacing changes update only spacing; neither operation hides control configuration in a getter or setter. The parent-only row changes no child input, though a direct measurement still accesses and fits the children.

Each trial creates independent direct and cached fixture sets. Warmup primes the cached entry before the final direct UIKit warmup, so configuration does not accidentally invalidate the direct baseline afterward. There are four direct warmup calls per warmed view; equivalent-view rows warm only their separate seed. Arm order alternates between trials. Both arms write their returned sizes into preallocated buffers; comparison, diagnostics, serialization, and attachment creation occur afterward. Loop and timer overhead are not subtracted.

### Results and cache observations

Every direct/cached size pair must match exactly and be finite with positive height. The report retains raw per-trial durations and checksums. Report medians and variability, absolute time per request, and cached/direct ratios; do not substitute measurement counts for elapsed-time results.

Standalone controls use measurement-closure counters in a separate untimed diagnostic replay. Timed closures do not contain those counters.

The existing document bundle has no measurement counters. Its diagnostic pass replays each exact request prefix into fresh storage, then uses the public `count` and `removeSize(of:toFit:)` operations to observe membership for the next request. A parent hit causes no child probe. A parent miss probes the actual child keys with their transformed proposals. Destructive probes are discarded with that replay's storage, so they cannot affect a later request. This bounded, quadratic replay is outside every timed trial and avoids changing the example or substituting a modeled LRU.

Document hit/miss counts are observed membership results. Document measurement counts are **inferred from misses**, not directly instrumented calls. The JSON distinguishes these from standalone closure counters. Cache entry bounds and expected warm/parent-only paths are checked outside timing. Mixed traces must show both hits and misses and, for content-dependent caches, eviction.

No allocation profiler is attached, and the UIKit harness does not report cache memory or allocation counts. Entry counts are not a memory measurement. Device and Simulator observations must be reported separately; Simulator timings do not predict physical-device timings.

### Investigating lookup cost

The same XCTest includes separate stable-input phases for warmed UIKit fitting, dependency capture, hashing a preconstructed snapshot, and a complete warm lookup. A fifth phase reads `UITextView.text`. These diagnostics use 512 operations and five trials per phase on the same warmed fixture, in fixed phase order. Snapshot and text reads write to 64 observation slots; size reads use a preallocated result buffer; hashes accumulate into an integer. Validation and checksums follow timing. The observation work is included, so subtracting these phases does not isolate equality or LRU bookkeeping. Use them to locate costs worth investigating, alongside the paired end-to-end measurements.

## Choosing dependencies for an application

Use ordinary stable values first. The core retains each selected value behind a private generic wrapper before erasure, preserving that value's concrete hashing and equality. Callers do not need to wrap arrays or other values to avoid element-wise erasure inside `AnyHashable`.

If a model already owns the authoritative text, select it by key path and keep the rendered view synchronized. The [model-text example](../Examples/Size-Caches.md#select-authoritative-model-text) uses `\.model.text` and the actual font. In the Simulator string comparison, identical long ASCII text cost 62.98 µs to hash after a UIKit read versus 1.26 µs from native model storage. Complete warm requests cost 149.75 versus 3.56 µs. This supports a representation-related explanation for much of the earlier text-view lookup cost; the generic core remains unchanged.

Explicitly making the UIKit string contiguous on every request improved that warm lookup to 36.70 µs, including conversion. It remained more expensive than selecting the existing model value, and changing-input workloads were dominated by configuration and measurement. The [full results](String-Results.md) include non-ASCII content, variability, and the limits of this comparison. Model strings can also have noncontiguous storage. Do not assume a storage representation from the property's type, or normalize every string without measuring the complete request.

If full-content hashing remains a bottleneck after that comparison, an optional compact semantic projection can reduce hashing work: a content identity together with a reliable revision that changes whenever any size-relevant content changes. Select existing identity and revision properties directly, or a computed immutable snapshot property when useful. The revision contract belongs to the application; identity alone cannot represent edits, and a revision that misses changes makes reuse incorrect. Do not reuse an identity/revision pair for different size-relevant content while affected entries may remain. Typography and other independent layout inputs still need their own dependencies.

Profile the application's actual hit rate, content, and fitting methods before choosing this projection. A small view with an inexpensive warm UIKit fit may be better served by direct measurement or one stored result. See the [README](../README.md) for the sizing and recursive reuse API.

## Synthetic diagnostics

Run the existing macOS release diagnostics with:

```sh
Benchmarks/run.sh
```

The [diagnostic methodology](Synthetic.md) separates snapshot construction, hashing, warm lookup, misses, and storage behavior. The [erasure comparison](Erasure-Results.md) records the internal representation repair. Historical samples remain available in [generic results](Results.md) and [size-facade results](Size-Results.md); their original toolchains, source fingerprints, and measurement limits still apply.
