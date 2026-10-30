# Tests and maintenance

Use the [specification](../SPEC.md) for implementation requirements and the [README](../README.md) for package usage.

## Run local checks

Use Xcode 27.1 with Swift 6.4 selected and Python 3 installed. Choose a fresh DocC output directory. From the repository root:

```sh
swift build
swift test --enable-code-coverage
swift build -c release
python3 Scripts/check-tests.py
python3 Scripts/check-tests.py --configuration release
python3 Scripts/check-concurrency.py --warnings-policy
python3 Scripts/check-preconditions.py
python3 Scripts/test-check-simulator.py
python3 Scripts/check-simulator.py
swift format lint --strict --recursive Package.swift Sources Tests
python3 Scripts/docs.py --output .build/docc-site
Benchmarks/run.sh
```

## Interpret validation results

The compiler script builds public-import controls under Swift 6 complete concurrency checking and warnings as errors. It also compiles the core, both UI support modules, and the UI example module, then real UIKit key-path and README fixtures, for an explicit iOS 16 simulator deployment target. SDK compilation establishes deployment compatibility, not runtime execution on iOS 16. The Simulator script discovers an installed runtime, observes every selected test, and removes only the device it creates.

Precondition fixtures execute in isolated debug child processes. Each invalid case must terminate abnormally with its intended diagnostic; valid controls must complete. They are outside the package test targets. Keep both valid and rejected compiler controls and these trap fixtures synchronized with the public contract.

## Measure UIKit performance

The [UIKit performance runner](../Benchmarks/README.md) runs XCTest benchmark fixtures in Release with coverage disabled. Use `python3 Benchmarks/run-uikit.py` for sizing and composition, or add `--suite strings` for UIKit/model text representation costs. Each command creates and removes an owned Simulator. The package's tool-hosted tests require an app host for physical-device execution; none is currently supplied. `python3 Benchmarks/test-run-uikit.py` checks both suites' result parsing. Ordinary test runs execute small correctness traces; timing trials are opt-in and do not use performance thresholds as unit-test assertions.

## Inspect generated documentation

The static site's entry is `/swift-derived-keys/documentation/`; its module pages are `derivedkeys/`, `derivedkeysui/`, and `derivedkeysuikit/` beneath it. Serve the output beneath `/swift-derived-keys/` to check deep links and assets. A build does not deploy documentation.

## Hosted workflows

The [Actions workflows](https://github.com/kylehughes/swift-derived-keys/actions) run checks and build static documentation. Documentation deployment is disabled while the repository is private, including manual runs with `deploy` selected.

### Publish documentation

The Documentation workflow responds to GitHub's [`public` event](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#public) when this repository changes from private to public. After that change, it builds and deploys DocC automatically; subsequent pushes to `main` update the site. GitHub Pages must use **GitHub Actions** as its publishing source, and the `github-pages` environment must allow deployments from `main`.

The deployment job consumes only its own run's `documentation-site` artifact. Before publishing, it checks the repository's current visibility, the configured Pages URL, and that the built commit is still the head of `main`. It does not change repository visibility. If an older run is superseded, use the current commit's run instead of publishing the old artifact.

The canonical entry is `https://kylehughes.github.io/swift-derived-keys/documentation/`. After the first public deployment, verify that entry, all three module pages, and their navigation and assets. A successful private build verifies the documentation artifact; live deployment needs a separate check.

To rebuild and deploy the current public `main` manually:

```sh
gh workflow run documentation.yml --repo kylehughes/swift-derived-keys --ref main -f deploy=true
```

### Prepare a versioned release

Manual release verification requires a version, exact candidate commit, and supplied notes unless generated notes are explicitly selected. Changing repository visibility does not create a version tag or release. Those operations require their own authorization. Keep examples, API comments, [the specification](../SPEC.md), and compiler fixtures aligned with the public API.
