# Tests and maintenance

Use Xcode 27.1 with Swift 6.4 selected and Python 3 installed. From the repository root:

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

The compiler script builds public-import controls under Swift 6 complete concurrency checking and warnings as errors. It also compiles the core, both UI support modules, and the UI example module, then real UIKit key-path and README fixtures, for an explicit iOS 16 simulator deployment target. SDK compilation establishes deployment compatibility, not runtime execution on iOS 16. The Simulator script discovers an installed runtime, observes every selected test, and removes only the device it creates.

Precondition fixtures execute in isolated debug child processes. Each invalid case must terminate abnormally with its intended diagnostic; valid controls must complete. They are outside the package test targets. Keep both valid and rejected compiler controls and these trap fixtures synchronized with the public contract.

Choose a fresh DocC output directory. The static site's entry is `/swift-derived-keys/documentation/`; its module pages are `derivedkeys/`, `derivedkeysui/`, and `derivedkeysuikit/` beneath it. Serve the output beneath `/swift-derived-keys/` to check deep links and assets. A build does not deploy documentation.

The [Actions workflows](https://github.com/kylehughes/swift-derived-keys/actions) run checks and prepare static documentation. Manual documentation deployment requires selecting `deploy` and configuring Pages access appropriate to the repository. Manual release verification requires a version, exact candidate commit, and supplied notes unless generated notes are explicitly selected. Deployment, tags, releases, and visibility changes require their own authorization. Keep examples, API comments, `SPEC.md`, and compiler fixtures aligned with the public API.
