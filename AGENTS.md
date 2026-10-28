# DerivedKeys

DerivedKeys separates dependency selection, immutable semantic keys, and synchronous bounded LRU reuse. Read [README.md](README.md) for public behavior and [maintenance](Documentation/Maintenance.md) for checks; [SPEC.md](SPEC.md) owns the implementation requirements.

- `DerivedKeys` is standard-library-only and nonisolated. Keep UI types out of this target.
- `DerivedKeysUI` is the key-path sizing facade. Recipes and recursive descriptions are immutable, read on the main actor, and keep capacity local. Both proposal axes and transitive full-value snapshots enter the key; parents never inspect child result storage to form keys.
- `DerivedKeysUIKit` is the supported fitting and layout-cache product. Its main-actor reference cache automatically keys the effective fitting proposal; captured inputs and result values remain caller-owned semantic contracts.
- `DerivedKeysUIExample` is a non-product target containing tested frame-layout and text/button examples. See [the sizing guide](Examples/Size-Caches.md) for fitting, cache sharing, and application layout responsibilities.
- `DocumentExportExample` is a runnable non-UI consumer; `DerivedKeysBenchmarks` measures key work and cache behavior in release mode.
- Swift tools 6.4, Swift 6 mode, macOS 13/iOS 16 minima, and warnings as errors are declared in `Package.swift`. Preserve those axes separately.

Keys retain complete values and structure, not hashes alone. Never weaken concrete type or operation separation. Hashable values can still have mutable aliases; callers must project stable values. Source identity is only request-local memoization identity. Sources are not Hashable or Sendable. Immutable graph edges and checked depth bound recursive evaluation. Cache entries must not retain providers or calculation closures. Keep optional nil hits, failed-computation noninsertion, LRU order, and copy independence covered.

Use Swift Testing with normal imports. Run `swift test --enable-code-coverage`, `python3 Scripts/check-concurrency.py`, and debug/release builds after semantic changes. The compiler fixtures include intentional failures; do not include them in package targets. Format production code with `swift format format --in-place --recursive Package.swift Sources Tests`, then strict lint. The maintenance commands build static DocC with a fresh output directory. Run release benchmarks using [Benchmarks/run.sh](Benchmarks/run.sh).

Use four-space indentation and the checked-in formatter settings. Prefer meaningful generic names and trailing `where` constraints. Document public equality, ownership, isolation, errors, and complexity where relevant. Keep examples and docs aligned with public APIs. Preserve peer edits. Repository instructions do not authorize deployment, releases, visibility changes, or history rewrites.

```sh
python3 Scripts/check-preconditions.py
python3 Scripts/test-check-simulator.py
python3 Scripts/check-simulator.py
```
