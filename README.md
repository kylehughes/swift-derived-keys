# DerivedKeys

[![Provenance: Software Factory](https://img.shields.io/badge/Provenance-Software_Factory-007AFF)](#provenance)
[![Swift tools: 6.4](https://img.shields.io/badge/Swift_tools-6.4-F05138)](Package.swift)
[![macOS minimum: 13+](https://img.shields.io/badge/macOS-13%2B-007AFF)](#compatibility)
[![iOS minimum: 16+](https://img.shields.io/badge/iOS-16%2B-007AFF)](#compatibility)

DerivedKeys caches calculations by the inputs that affect their results. A custom UIKit view can reuse its measured size and child frames when its content and fitting bounds are unchanged, including across different view instances. Model identity and general-purpose equality stay unchanged.

The package separates dependency selection, immutable key snapshots, and a bounded LRU cache. Use concrete keys for fixed schemas, or compose live sources when the dependency graph is assembled at runtime. Equal keys must mean interchangeable results; the library cannot discover missing dependencies for you.

## Cache a custom view's layout

Add the `DerivedKeysUIKit` product for this example. `LabelView` uses manual frames and retains a bounded cache for its lifetime. Both `sizeThatFits(_:)` and `layoutSubviews()` request the same layout: the supplied width and the text's natural height. The cached result contains the complete size and label frame.

```swift
import DerivedKeysUIKit
import UIKit

@MainActor
final class LabelView: UIView {
    enum Operation {}
    struct Context: Hashable {}
    struct Layout {
        let size: CGSize
        let labelFrame: CGRect
    }

    private let cache = LayoutCache<Operation, String, Context, Layout>(capacity: 32)
    private let label = UILabel()

    var text: String {
        didSet {
            label.text = text
            setNeedsLayout()
        }
    }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        Self.configure(label, text: text)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        text = ""
        super.init(coder: coder)
        Self.configure(label, text: text)
        addSubview(label)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        layout(forWidth: size.width)?.size ?? .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = layout(forWidth: bounds.width)?.labelFrame
            .offsetBy(dx: bounds.minX, dy: bounds.minY) ?? .zero
    }

    private func layout(forWidth width: CGFloat) -> Layout? {
        guard let proposal = try? FittingProposal(
            fitting: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ) else { return nil }

        return cache.value(for: text, proposal: proposal, context: Context()) { text, proposal, _ in
            let padding: CGFloat = 12
            let width = proposal.fittingSize.width
            let unbounded = proposal.width.limit == nil
            let innerWidth = unbounded ? width : max(0, width - padding * 2)
            let measuringLabel = UILabel()
            Self.configure(measuringLabel, text: text)
            let measured = innerWidth > 0
                ? measuringLabel.sizeThatFits(CGSize(width: innerWidth, height: CGFloat.greatestFiniteMagnitude))
                : .zero
            let height = ceil(measured.height)
            let outerWidth = unbounded ? ceil(measured.width) + padding * 2 : width
            return Layout(
                size: CGSize(width: outerWidth, height: height + padding * 2),
                labelFrame: CGRect(
                    x: min(padding, outerWidth / 2), y: padding,
                    width: max(0, outerWidth - padding * 2), height: height
                )
            )
        }
    }

    private static func configure(_ label: UILabel, text: String) {
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .left
        label.semanticContentAttribute = .forceLeftToRight
    }
}
```

The parent measures the view and assigns its frame on the main actor:

```swift
let view = LabelView(text: "A paragraph whose height depends on its available width.")
let size = view.sizeThatFits(CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
view.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: size)
view.layoutIfNeeded() // Reuses the layout calculated by sizeThatFits.
```

Changing the text or width produces a different key. Repeated fitting and layout reuse the retained result. Paint-only changes can leave the key unchanged. The miss calculation configures a fresh label from the captured text, so it measures the same inputs used to form the key.

This example fixes typography, wrapping, direction, and padding, so its context is empty. It ignores proposed height, rounds height to whole points, and fills a finite proposed width. Widths smaller than the padding yield a zero-width label; invalid widths return zero. The greatest-finite-magnitude sentinel requests natural width. These are the view's policies: the cache itself neither rounds nor clamps results. If your layout reads fonts, traits, insets, or other state, capture those values in its inputs or context.

The [tested implementation](Sources/DerivedKeysUIExample/LabelView.swift) also supports injecting a shared cache. The [UIKit guide](Examples/UI-Measurement.md) covers fitting, sharing, and composing child keys. A small view with a single remembered size may need only its own request struct and stored result; DerivedKeys adds complete request composition and bounded reuse across multiple inputs.

## Installation

Add `https://github.com/kylehughes/swift-derived-keys` in Xcode's package dependencies and select `DerivedKeysUIKit` for view layout caching or `DerivedKeys` for the generic key and cache APIs. Repository access is required. The development reference is `main`:

```swift
.package(url: "https://github.com/kylehughes/swift-derived-keys", branch: "main")
```

Then add `.product(name: "DerivedKeysUIKit", package: "swift-derived-keys")` to your target's dependencies. Add the `DerivedKeys` product too when importing its lower-level APIs directly. The core uses only the Swift standard library; `DerivedKeysUIKit` adds fitting proposals and main-actor layout caching. Demonstration views remain example source, separate from the supported library products.

## Selecting dependencies

### Fixed schemas and explicit snapshots

Use a small `Hashable` value struct for the inputs of one operation. `RequestKey<Operation, Dependencies, Context>` adds a nominal operation type, algorithm version, and environment. Declare a separate operation enum for unrelated calculations, including when storing requests in an `AnyHashable` dictionary. A free-form label does not separate operations.

`OriginalKey` labels one captured value. `DerivedKey` labels a composition, and `KeyPair` holds two heterogeneous children without type erasure. Domain structs make larger fixed schemas readable. `KeyProjection` stores a reusable synchronous function from explicit input to dependencies:

```swift
import DerivedKeys

enum ExportOperation {}
struct ExportInput: Hashable {
    let text: String
    let uppercase: Bool
}

let projection = KeyProjection(operation: ExportOperation.self) { (input: ExportInput) in
    DerivedKey("export", children: input)
}
let input = ExportInput(text: "Hello", uppercase: true)
let key = projection.key(for: input, context: "plain-text")
```

Keep every value's equality and hashing stable for the lifetime of a key. `Hashable` does not ensure immutability: copying a mutable class reference is not a snapshot. Project its content into immutable values instead. A content ID alone cannot describe edits under that ID; a revision is sufficient only with complete mutation coverage, a unique content identity, and a non-reuse contract.

### Runtime composition and live reads

`KeySource<Input>` is an immutable graph recipe. Providers run when `snapshot(for:)` is called. Sources are deliberately not dictionary keys; `DependencySnapshot` is the evaluated key material.

```swift
let text = KeySource<ExportInput>("text") { $0.text }
let options = KeySource<ExportInput>("uppercase") { $0.uppercase }
let source = try KeySource("export", children: [text, options])
let input = ExportInput(text: "Hello", uppercase: true)
let key = RequestKey(
    operation: ExportOperation.self,
    dependencies: source.snapshot(for: input),
    context: "plain-text"
)
```

The closure convenience requires `@Sendable`, so an actor-isolated closure cannot be silently stored as a nonisolated callback. Inputs and returned `Hashable` values need not be `Sendable`. For live non-Sendable state, conform a reader to `KeyValueProvider` and pass it as `provider:`. Its `nonisolated value(for:)` method makes the execution contract explicit without making the reader transferable. `KeyProjection` also accepts this reader form. Keep that state within its mutation owner.

Providers must be synchronous, side-effect-free reads: no I/O, mutation, suspension, or recursive evaluation. Actor-isolated properties belong in an explicit snapshot captured by the actor before calling the source. Sources retain their providers, so avoid owner/source capture cycles; evaluated keys and cache entries do not retain those providers. A weak-owner adapter should represent a missing owner explicitly, never fabricate a valid dependency value.

Each distinct source is read once per evaluation, even when shared by several parents. That memoization does not synchronize different properties or sources. Capture related state together, then calculate from the same snapshot without an intervening mutation. No change notification or `update()` call is needed. When values return A → B → A, the original key is restored.

Composition preserves labels, original versus derived nodes, concrete value types, order, multiplicity, optional presence, and nested boundaries. Empty derived compositions are valid. `appending` returns a new derived source; rebinding a child variable does not change an existing composition. Build large collections with `init(_:children:)`: repeated appends copy the child array. Graph depth is limited to 64 nodes per path; construction throws beyond that bound. Immutable edges prevent graph cycles.

Arrays preserve order. For unordered inputs, use a `Set`, a dictionary with its own order-independent `Hashable` semantics, or canonicalize according to the calculation. Do not turn incidental dictionary iteration order into an ordered dependency list.

## Cache behavior and ownership

`MemoizationCache<Key, Value>` requires an explicit nonnegative capacity. Zero disables storage. Hits and successful insertions become most recently used; overflow evicts the least recently used entry. A hit skips the calculation. A thrown calculation propagates its error without insertion or eviction; a cached optional `nil` is a hit. Use `removeValue(for:)`, `removeAll()`, and `count` to manage storage.

The cache is a value type with exclusive mutation. Copies evolve independently, with standard-library copy-on-write costs on later mutation. Reentering the same cache during its calculation is unsupported; separate caches can be composed. Results, like keys, must not change meaning through mutable external aliases. Computations whose side effects must run on every call do not belong in this cache.

Typed keys and caches are `Sendable` only when their stored values are. Dynamic sources, projections, and erased snapshots are not `Sendable`. Their input and captured value types need no transfer conformance; non-Sendable live readers use `KeyValueProvider`, while the closure conveniences require `@Sendable`. The generic library has no main-actor requirement. `DerivedKeysUIKit.LayoutCache` is a main-actor reference type: sharing it shares its entries and recency order. It automatically includes the effective fitting proposal and supplies captured inputs to the calculation. Results can be `CGSize` or your own layout struct. It does not retain calculation closures; callers control the values retained by keys and results. Changing a model, scheduling layout, and assigning the resulting size remain application responsibilities.

Dictionary indexing and LRU bookkeeping are expected amortized O(1), excluding key hashing/equality and copy-on-write. Key work can grow with content size and repeated child occurrences. The capacity bounds entry count, not bytes: retained keys and results both matter. Use reusable immutable projections at controlled content-mutation boundaries when profiling warrants it. Swift `Hasher` output is process-local; never persist it or replace a semantic key with its integer hash.

## Examples and documentation

The [UIKit guide](Examples/UI-Measurement.md) covers complete layout caching, shared ownership, and request composition. The [text/button example](Examples/Text-Component.md) shows independently cached child measurements. For a non-UI use, read the [document exporter](Examples/Document-Export.md) or run `swift run DocumentExportExample`; it uses ordered paragraphs, format, and export options while ignoring selection and scrolling.

The [UIKit API overview](Documentation/DerivedKeysUIKit.docc/DerivedKeysUIKit.md) covers fitting and cache contracts. The [core overview](Documentation/DerivedKeys.docc/DerivedKeys.md) links the key APIs and [dependency design guide](Documentation/DerivedKeys.docc/DependencyDesign.md). [Release benchmarks](Benchmarks/README.md) separate key work from computation, explain workloads, and report memory-measurement limits.

## Compatibility

The package declares Swift tools 6.4, Swift 6 language mode, macOS 13.0+, and iOS 16.0+. Default actor isolation is nonisolated; Swift 6 strict concurrency checking applies. Every owned Swift target treats compiler warnings as errors. `DerivedKeys` uses only the Swift standard library. `DerivedKeysUIKit` uses CoreGraphics for fitting geometry; its proposals and cache also compile on macOS. The example views and UIKit measurement tests exist only where UIKit is available.

## Maintenance

From the repository root with Xcode 27.1 selected and Python 3 installed:

```sh
swift build
swift test --enable-code-coverage
swift build -c release
python3 Scripts/check-tests.py --configuration release
python3 Scripts/check-concurrency.py --warnings-policy
python3 Scripts/test-check-simulator.py
python3 Scripts/check-simulator.py
swift format lint --strict --recursive Package.swift Sources Tests
python3 Scripts/docs.py --output .build/docc-site
```

Choose a fresh output directory for each DocC build. The static site's entry is `/swift-derived-keys/documentation/`, with module pages at `derivedkeys/` and `derivedkeysuikit/` beneath it; serve the output beneath `/swift-derived-keys/` to test deep links. The [Actions workflows](https://github.com/kylehughes/swift-derived-keys/actions) build/test the package, prepare static documentation, and provide a manual release operation. Documentation deployment requires explicitly selecting `deploy` on a manual run and configuring Pages access appropriate to the repository. A documentation build alone does not deploy it.

The manual release workflow requires a version, exact candidate commit, and supplied notes unless generated notes are explicitly selected. It verifies the candidate before a separate publisher creates release artifacts. Deployment, tags, releases, and repository visibility changes require their own authorization. Keep README examples, API comments, compiler fixtures, and compatibility settings synchronized when changing the public contract.

## Contributions

DerivedKeys is not accepting source contributions at this time. Bug reports will be considered.

## Provenance

DerivedKeys was implemented from Kyle Hughes' technical specification using the Swift Package Factory workflow and Codex.

## Author

[Kyle Hughes](https://kylehugh.es)

[![Bluesky](https://img.shields.io/badge/Bluesky-0285FF?logo=bluesky&logoColor=fff)](https://bsky.app/profile/kylehugh.es)<br>
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?logo=linkedin&logoColor=fff)](https://www.linkedin.com/in/kyle-hughes)<br>
[![Mastodon](https://img.shields.io/mastodon/follow/109356914477272810?domain=https%3A%2F%2Fmister.computer&style=social)](https://mister.computer/@kyle)

## License

DerivedKeys is available under the [MIT License](LICENSE).
