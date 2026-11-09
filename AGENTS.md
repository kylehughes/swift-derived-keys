# DerivedKeys

DerivedKeys separates dependency selection, immutable semantic keys, and synchronous bounded LRU reuse. Read [README.md](README.md) for public behavior and [maintenance](Documentation/Maintenance.md) for checks; [SPEC.md](SPEC.md) defines the implementation requirements.

## Package boundaries

- `DerivedKeys` is standard-library-only and nonisolated; keep all UI types out of this target. `ResultCache` binds a nonthrowing recipe to selected key paths with value-semantic storage. Its types take ordinary key paths and closures with no `Sendable` requirement and are not `Sendable`; Swift 6 region isolation confines an instance built from actor-isolated inputs to that actor, so a `@MainActor` type can own a `ResultCache` directly.
- `DerivedKeysUI` is the sole UI product. It provides `SizeCache`, `SizeCacheBinding`, `SizeDependencies`, `MainActorResultCache`, `LayoutCache` (`LayoutInputs`, `LayoutKey`), and `FittingProposal` (`FittingDimension`, `FittingProposalError`). Recipes and child descriptions are immutable, read on the main actor, and keep capacity local. Both proposal axes and transitive full-value snapshots enter a `SizeCache` key; parents never inspect child result storage when forming keys.
- `MainActorResultCache` caches arbitrary values by selected key paths on the main actor with reference semantics and a reentry precondition. It has no implicit fitting proposal or child composition.
- `LayoutCache` automatically keys the effective fitting proposal and has no `version` parameter; callers own the semantics of captured inputs and result values. Reentering it during a calculation fails a precondition.
- `DerivedKeysUIExample` is a non-product target containing tested frame-layout and text/button examples; see [the sizing guide](Examples/Size-Caches.md) for fitting, cache sharing, and application layout responsibilities.
- `DocumentExportExample` is a runnable non-UI consumer. [UIKit benchmarks](Benchmarks/README.md) compare real sizing paths, while `DerivedKeysBenchmarks` covers synthetic key and cache diagnostics.
- `Package.swift` requires Swift tools 6.4, Swift 6 language mode, macOS 13 / iOS 16 minimums, and warnings as errors. Preserve each requirement separately.

## Key and storage contracts

[The cache contract](Documentation/DerivedKeysUI.docc/CacheContract.md) states the user-facing rules once: complete selection, stable values, retention, reentrancy, proposals, declared children, and clearing. Link to it from guides and doc comments instead of restating it, and keep it synchronized with [SPEC.md](SPEC.md).

Keys retain complete values and structure, never hashes alone, and must preserve concrete type and operation separation. Because `Hashable` classes can still mutate through aliases, callers must project stable values. `KeySource` object identity is used only for request-local memoization; sources are neither `Hashable` nor `Sendable`, and immutable graph edges with a checked 64-node depth limit bound recursive evaluation.

`DependencySnapshot` erases each leaf with a private class box that preserves concrete type identity, equality, and hashing—do not reintroduce `AnyHashable`. The core's hot generic paths are `@inlinable` (with hand-written typed-key `==` and `hash(into:)`) so client modules specialize them. Verify any change to those paths with synthetic benchmarks and, for sizing paths, UIKit benchmarks. Ordinary callers must not need custom wrappers to avoid internal erasure overhead.

Cache entries must not retain providers or per-request calculation closures. Preserve test coverage for `Optional.none` hits, non-insertion after thrown errors, LRU eviction order, and value-copy independence.

`ResultCache` and `MainActorResultCache` retain one recipe and key ordered `DependencySnapshot` values with the bounded LRU. Only selected key paths enter the key, including explicitly selected named tuple fields (`\.self` selects the whole input). Do not add `@Sendable` or `Sendable` requirements to the core facade's key paths, closures, inputs, or results. `MainActorResultCache` guards against reentry across dependency capture, calculation, `count` inspection, and removal. Entries never implicitly retain lookup roots, though recipe captures, reference-valued dependencies, and results can. See [result stages](Examples/Result-Caches.md) for ownership and the TextKit line-count example.

## Sizing API and ownership

Prefer the UIKit convenience initializers (`SizeCache<UITextView>`, `SizeCache<UIButton>`, and other `UIView` subclasses) for leaf measurements. They bind `sizeThatFits(_:)`, accept no children, and are exempt from the debug undeclared-child check. Composed parents use the closure initializer, declare children in `children:`, and measure through those same child handles. Custom leaf recipes remain available for non-standard measurement policies.

`bound(to:)` is the only way to map a child cache onto a parent root: the returned `SizeCacheBinding` retains the child cache and uses the same key path for both dependency capture and measurement. A cache retains its configured recipe (and any child handles or objects the recipe captures), while entries never retain measured roots. Never call a `SizeCache` from a `sizeThatFits(_:)` override that the cache's own miss recipe invokes.

In debug builds, a `SizeCache` lookup inside another size cache's recipe asserts unless the running parent declared that cache (directly or transitively in `children:`) or passed `allowsUndeclaredMeasurements: true`. A lookup through a binding rooted at the running parent must also match a declared key path. Keep this check and all of its state inside `#if DEBUG`: running that bookkeeping in release builds caused bindings to keep caches alive after release, which `Scripts/test-release.py` checks. Proposal axes treat `+infinity` and `CGFloat.greatestFiniteMagnitude` alike as unconstrained, and fail on NaN, `-infinity`, or negative values.

Composition does not dictate cache ownership. Any unselected size-affecting property must remain constant for the cache's lifetime and match across all roots sharing that cache; select variable properties as dependencies. When selecting model key paths, keep the rendered view synchronized with the authoritative model before lookup. See [the sizing guide](Examples/Size-Caches.md) for full examples.

## Implementation and checks

Write unit tests with Swift Testing and normal imports; UIKit performance fixtures use XCTest. After any semantic change, run the full [local checks](Documentation/Maintenance.md#run-local-checks) sequence: coverage, debug and release builds, verified test execution (`python3 Scripts/check-tests.py` and `python3 Scripts/check-tests.py --configuration release`), concurrency and warnings-as-errors probes (`python3 Scripts/check-concurrency.py --warnings-policy`), precondition traps, release lifetime checks, Simulator test execution, formatting, static DocC, and synthetic benchmarks. Keep compiler fixtures (which include intentional compile errors) outside package targets. Note that the iOS 16 compilation check verifies build compatibility, not runtime execution on iOS 16.

Use four-space indentation and the repository's `.swift-format` configuration. Format production and test code with `swift format format --in-place --recursive Package.swift Sources Tests`, then run strict lint (`swift format lint --strict --recursive Package.swift Sources Tests`), and format/lint any modified valid compiler fixtures separately. Use descriptive generic parameter names and trailing `where` clauses, and document equality, ownership, isolation, errors, and complexity on public APIs.

Keep code fences in README, guides, and DocC synchronized with their compiled fixture companions: [README generic example](Fixtures/Concurrency/READMEGenericExample.swift), [generic documentation examples](Fixtures/Concurrency/DocumentationExamples.swift), [README UIKit examples](Fixtures/iOS/READMEExamples.swift), and [UIKit documentation examples](Fixtures/iOS/DocumentationExamples.swift). `Scripts/check-concurrency.py` compiles these fixture files rather than extracting Markdown blocks directly. Always build static DocC into a fresh output directory.

Write user-facing docs for a public `1.0.0` release (update the minimum version when a newer stable release ships), and keep private-repo or branch instructions in maintainer docs.

Preserve peer edits. Repository instructions do not authorize deployment, releases, visibility changes, or history rewrites.

## UIKit benchmarks

Run UIKit performance trials in Release without coverage via `python3 Benchmarks/run-uikit.py`; ordinary XCTest runs execute a small functional control trace. Keep UIKit configuration and warmup equivalent between direct and cached arms, record observed hits and misses separately from inferred measurement counts, keep cache capacity independent of iteration count, and report Simulator and physical-device timings separately. Run `python3 Benchmarks/test-run-uikit.py` after modifying runner or parser code.
