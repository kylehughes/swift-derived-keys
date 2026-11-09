# Tests and maintenance

See the [specification](../SPEC.md) for implementation requirements and the [README](../README.md) for package usage.

## Run local checks

Prerequisites:

- **Xcode:** 27.1 selected
- **Swift:** 6.4
- **Python:** 3

Choose a fresh DocC output directory (`--output` fails if the directory already exists) and run the full check suite from the repository root:

```sh
swift build
swift test --enable-code-coverage
swift build -c release
python3 Scripts/check-tests.py
python3 Scripts/check-tests.py --configuration release
python3 Scripts/check-concurrency.py --warnings-policy
python3 Scripts/check-preconditions.py
python3 Scripts/test-release.py
python3 Scripts/test-documentation.py
python3 Scripts/test-check-simulator.py
python3 Scripts/check-simulator.py
swift format lint --strict --recursive Package.swift Sources Tests
python3 Scripts/docs.py --output .build/docc-site
Benchmarks/run.sh
```

## Interpret validation results

- **Concurrency and iOS 16 compilation (`Scripts/check-concurrency.py --warnings-policy`):** Builds public-import controls under Swift 6 complete concurrency checking with warnings treated as errors, including negative fixtures that must fail to compile. It also cross-compiles `DerivedKeys`, `DerivedKeysUI`, `DerivedKeysUIExample`, and the UIKit key-path and README fixtures against an explicit iOS 16 Simulator deployment target. This verifies iOS 16 source and deployment-target compatibility; it does not execute tests on an iOS 16 runtime.
- **Preconditions (`Scripts/check-preconditions.py`):** Runs precondition fixtures in isolated debug child processes outside the package test targets. Invalid calls must trap with the expected diagnostic message, and valid controls must exit cleanly. Keep both compiler fixtures and precondition fixtures in sync with the public API contract.
- **iOS Simulator tests (`Scripts/check-simulator.py`):** Finds an installed iOS Simulator runtime, creates a temporary Simulator device, verifies that every selected test runs, and deletes only the device it created.

## Measure UIKit performance

The [UIKit performance runner](../Benchmarks/README.md) executes XCTest benchmark fixtures in Release with code coverage disabled:

- Run `python3 Benchmarks/run-uikit.py` for view sizing and child-cache composition.
- Run `python3 Benchmarks/run-uikit.py --suite strings` for UIKit versus model string lookup costs.
- Run `python3 Benchmarks/test-run-uikit.py` to test result parsing for both suites.

When no destination is passed, the runner creates and deletes its own Simulator. Because the package uses tool-hosted tests and does not include a host app target, these fixtures cannot run on a physical device as configured. During ordinary `swift test` or `xcodebuild test` runs, the benchmark test case runs a small functional correctness trace rather than timing trials, and never asserts on wall-clock thresholds.

## Inspect generated documentation

`Scripts/docs.py` extracts symbol graphs for both macOS and the iOS 16 Simulator using the active Xcode toolchain, then merges them into a single DocC archive so UIKit-only symbols appear alongside the macOS API. The script fails if either module page, either `SizeCache` initializer page, or the UIKit convenience initializer's `Root inherits UIView` availability constraint is missing from the rendered output.

Building the site locally does not deploy it. The generated site's root path is `/swift-derived-keys/documentation/`, with module pages at `derivedkeys/` and `derivedkeysui/` underneath; serve the output directory under `/swift-derived-keys/` when checking deep links and static assets locally.

## Hosted workflows

The [GitHub Actions workflows](https://github.com/kylehughes/swift-derived-keys/actions) run CI checks, publish DocC documentation, and verify release candidates.

### Publish documentation

The Documentation workflow (`documentation.yml`) builds and deploys the DocC site on pushes to `main` and when the repository transitions to public. The GitHub Pages site is public even while the source repository is private. In repository settings, GitHub Pages must use **GitHub Actions** as its build source, and the `github-pages` environment must permit deployments from `main`.

The deploy job publishes only the `documentation-site` artifact produced by its own workflow run. Before publishing, its guard script verifies the canonical repository (`kylehughes/swift-derived-keys`), the public Pages URL, and that the built commit is still the `HEAD` of `main`; it never alters repository visibility. If a newer push supersedes a run on `main`, trigger or use the latest commit's run instead of re-running the stale job.

A green build confirms only that the artifact built cleanly; verify the live site at `https://kylehughes.github.io/swift-derived-keys/documentation/`, including both module pages, navigation, and static assets, after deployment completes.

To rebuild and deploy `main` manually:

```sh
gh workflow run documentation.yml --repo kylehughes/swift-derived-keys --ref main -f deploy=true
```

### Prepare a versioned release

The manual release workflow requires a semantic version, the exact candidate commit SHA, and release notes (unless generated notes are explicitly enabled). Making the repository public does not tag or publish a release; visibility changes and releases are authorized separately. Before cutting a release, verify that the README, guides, doc comments, [specification](../SPEC.md), and compiler fixtures all match the public API.
