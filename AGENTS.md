# DerivedKeys

DerivedKeys separates dependency selection, immutable semantic keys, and synchronous bounded LRU reuse. Read [README.md](README.md) for public behavior and [maintenance](Documentation/Maintenance.md) for checks; [SPEC.md](SPEC.md) defines the implementation requirements.

## Package boundaries

- `DerivedKeys` is standard-library-only and nonisolated. Keep UI types out of this target.
- `DerivedKeysUI` is the key-path sizing facade. Recipes and recursive descriptions are immutable, read on the main actor, and keep capacity local. Both proposal axes and transitive full-value snapshots enter the key; parents never inspect child result storage to form keys.
- `DerivedKeysUIKit` is the supported fitting and layout-cache product. Its main-actor reference cache automatically keys the effective fitting proposal; captured inputs and result values remain caller-owned semantic contracts.
- `DerivedKeysUIExample` is a non-product target containing tested frame-layout and text/button examples. See [the sizing guide](Examples/Size-Caches.md) for fitting, cache sharing, and application layout responsibilities.
- `DocumentExportExample` is a runnable non-UI consumer. [UIKit benchmarks](Benchmarks/README.md) compare real sizing paths; `DerivedKeysBenchmarks` retains synthetic key and cache diagnostics.
- Swift tools 6.4, Swift 6 mode, macOS 13/iOS 16 minima, and warnings as errors are declared in `Package.swift`. Preserve each requirement separately.

## Key and storage contracts

Keys retain complete values and structure, not hashes alone. Never weaken concrete type or operation separation. Hashable values can still have mutable aliases; callers must project stable values. Source identity is only request-local memoization identity. Sources are not Hashable or Sendable. Immutable graph edges and checked depth bound recursive evaluation.

Preserve concrete hashing and equality through type erasure in both direct snapshots and `KeySource` construction. `DependencySnapshot` wraps each value in a private generic `Hashable` type before erasing it with `AnyHashable`; this avoids expensive element erasure for arrays. Representation changes need correctness coverage and representative UIKit benchmark evidence. Ordinary callers must not need custom wrappers to avoid internal overhead.

Cache entries must not retain providers or per-request calculation closures. Keep optional nil hits, noninsertion after failed calculations, LRU order, and copy independence covered.

## Sizing API and ownership

Prefer native `SizeCache<UITextView>` or `SizeCache<UIButton>` initializers for UIKit leaf measurements. These bind `sizeThatFits(_:)` and accept no children. Composed parents declare children and supply a custom recipe that measures through those same child handles. Custom leaf recipes remain available for other measurement policies.

Use `bound(to:)` when a parent needs a mapped child measurement handle: the binding retains the child cache and uses the same root mapping for dependencies and measurement. Use `at(_:)` when only a mapped dependency description is needed; it retains no child result storage. Child descriptions retain dependency readers. A cache retains its configured recipe, which may capture child handles or other objects. Entries do not implicitly retain measured roots; user captures and reference-valued dependencies can retain them. Never route a recipe back through a `sizeThatFits(_:)` override that reenters the same cache.

Composition does not dictate ownership. Unselected size-affecting settings must stay fixed for the cache's lifetime and match across every root sharing it. Declare variable inputs as dependencies. Keep authoritative model values synchronized with the measured view when selecting model key paths. See [the sizing guide](Examples/Size-Caches.md) for complete examples and contracts.

## Implementation and checks

Use Swift Testing with normal imports for unit tests; UIKit performance fixtures use XCTest. After semantic changes, run the full [local checks](Documentation/Maintenance.md#run-local-checks) checklist. It includes coverage, debug/release builds, observed test execution, compiler and precondition fixtures, release and Simulator controls, formatting, static DocC, and synthetic benchmarks. Run `python3 Scripts/check-tests.py` and `python3 Scripts/check-tests.py --configuration release` to verify every selected test executes. Use `python3 Scripts/check-concurrency.py --warnings-policy` to include the debug/release warnings-as-errors probes. Compiler fixtures include intentional failures; keep them outside package targets. An iOS 16 compilation check does not establish execution on iOS 16.

Use four-space indentation and the checked-in formatter settings. Format production code with `swift format format --in-place --recursive Package.swift Sources Tests`, then strict lint. Format and lint changed valid compiler fixtures separately. Prefer meaningful generic names and trailing `where` constraints. Document public equality, ownership, isolation, errors, and complexity where relevant.

Keep README, guide, and DocC snippets synchronized with their compiler companions: [README generic example](Fixtures/Concurrency/READMEGenericExample.swift), [generic documentation examples](Fixtures/Concurrency/DocumentationExamples.swift), [README UIKit examples](Fixtures/iOS/READMEExamples.swift), and [UIKit documentation examples](Fixtures/iOS/DocumentationExamples.swift). The compiler script discovers these fixtures automatically; it does not extract or compile Markdown code fences. Build static DocC into a fresh output directory using the maintenance commands.

Write user-facing documentation for a public stable release. Installation examples use a version requirement starting at `1.0.0`; update that version when a newer stable release ships. Keep private-repository access and development-branch instructions in maintainer documentation.

Preserve peer edits. Repository instructions do not authorize deployment, releases, visibility changes, or history rewrites.

## UIKit benchmarks

UIKit performance trials use `python3 Benchmarks/run-uikit.py` in Release without coverage; the ordinary XCTest invocation runs cheap functional controls. Preserve equivalent UIKit configuration and warmup in both measured arms. Record actual hit/miss observations separately from inferred measurement counts, keep capacity independent of iterations, and report Simulator and physical-device results separately. Check runner parsing with `python3 Benchmarks/test-run-uikit.py` after tooling changes.
