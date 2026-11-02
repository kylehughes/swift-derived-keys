# DerivedKeys

[![Provenance: Software Factory](https://img.shields.io/badge/Provenance-Software_Factory-007AFF)](#provenance)
[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Test](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml/badge.svg)](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml)

DerivedKeys builds cache keys from the values a computation depends on. Its sizing API lets you cache a view's size by declaring the properties that affect layout, then compose child caches to cache an entire layout. The underlying keys and bounded memoization are general-purpose Swift APIs.

Use `DerivedKeysUI` for view sizing. For computations without UI, start with the [generic core](#use-the-generic-core).

[Sizing walkthrough](#sizing-views) · [Installation and products](#install-and-import) · [Cache rules](#use-the-cache-correctly) · [Documentation and maintenance](#further-documentation)

## Sizing views

Create caches once in a retained main-actor owner. The walkthrough starts with one measurement, combines it with another, then [injects the caches into a view](#choose-ownership).

### Cache one measurement

The UIKit convenience initializer calls `sizeThatFits(_:)` on the view passed to lookup. Select the properties that can change the measurement. Every view measured through one cache must use the same unselected measurement settings. Select settings that vary between views or requests, or use separate caches for different fixed configurations.

Here `view` is an application `DocumentContentView` that exposes its text and button controls. The [complete example](Sources/DerivedKeysUIExample/DocumentContentView.swift) fixes the text view's wrapping, insets, padding, and scrolling configuration.

```swift
import DerivedKeysUI
import UIKit

let textSizes = SizeCache<UITextView>(
    dependingOn: \.text,
    \.font,
    \.textContainer.maximumNumberOfLines,
    capacity: 256
)

let availableSize = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
let size = textSizes.size(of: view.textView, toFit: availableSize)
```

The view passed to `size(of:toFit:)` is the cache's **root**; the fitting **proposal** is the size you would pass to `sizeThatFits(_:)`. A lookup reads the selected values and automatically includes **both fitting dimensions** in the key. On a miss, this initializer calls the text view's `sizeThatFits(_:)` with the normalized proposal. The root view itself is not part of the key, so equivalently configured views can share results. Selected values must be `Hashable` and stable; the root needs neither `Hashable` nor `Sendable` conformance.

If your model already owns the displayed text, consider [selecting that authoritative value](Examples/Size-Caches.md#select-authoritative-model-text). The recorded Simulator workload found cheaper repeated requests with its native model strings than with identical text read back from UIKit. Keep the model and rendered text synchronized; a Swift `String` property alone does not guarantee a particular storage representation.

Use finite, nonnegative proposal dimensions; `CGFloat.greatestFiniteMagnitude` is supported for an unconstrained axis. See [fitting proposals](#fitting-proposals) for validation and normalization rules. A cache hit skips the measurement recipe—the calculation configured for that cache—so side effects that must run on every request belong outside it.

For a small view with one remembered size, an ordinary request struct and stored result may suffice. These APIs let you compose dependencies and retain results for several input states within a fixed capacity. A hit still pays for dependency reads, snapshot construction, hashing, and equality. In the [recorded Simulator run](Benchmarks/UIKit-Native-Fitting-Results.md), warm composed parents and some shared measurements benefited; already-warm labels and the low-hit mixed parent trace favored direct UIKit fitting. Use the [benchmark methodology](Benchmarks/README.md) to evaluate your own workload.

### Compose a layout

Add a button measurement, then bind each child cache to its path in the parent. Use those same handles in the layout calculation.

Both `textSizing` and `buttonSizing` have type `SizeCacheBinding<DocumentContentView>`. They read child dependencies and look up sizes through their selected paths using the original caches. Their `size(of:toFit:)` calls therefore take the parent content view:

```swift
let buttonSizes = SizeCache<UIButton>(
    dependingOn: \.currentTitle,
    \.titleLabel?.font,
    capacity: 256
)
let textSizing = textSizes.bound(to: \DocumentContentView.textView)
let buttonSizing = buttonSizes.bound(to: \DocumentContentView.button)

let contentSizes = SizeCache<DocumentContentView>(
    dependingOn: \.padding,
    \.spacing,
    \.showsButton,
    children: textSizing, buttonSizing,
    capacity: 256
) { content, proposal in
    let innerProposal = CGSize(
        width: max(0, proposal.width - 2 * content.padding),
        height: CGFloat.greatestFiniteMagnitude
    )
    let textSize = textSizing.size(of: content, toFit: innerProposal)
    let buttonSize = content.showsButton
        ? buttonSizing.size(of: content, toFit: innerProposal)
        : .zero
    return CGSize(
        width: proposal.width,
        height: 2 * content.padding + textSize.height + buttonSize.height
            + (content.showsButton ? content.spacing : 0)
    )
}

let initial = contentSizes.size(of: view, toFit: availableSize)
view.spacing += 4
let spaced = contentSizes.size(of: view, toFit: availableSize) // Parent miss; children hit.
view.content += " Another paragraph."
let edited = contentSizes.size(of: view, toFit: availableSize) // Parent and text miss; button hits.
```

The button's other measurement settings are fixed, including its configuration. The calculation captures the same bound handles declared in `children:`. A parent hit skips its calculation and all child result lookups. A parent miss executes the calculation, whose child lookups can independently hit.

Proposal transformation appears only in the calculation. Padding affects the inner width, so padding belongs in the parent's dependencies; each child keys the actual proposal it receives. The example expects an actual available width and returns that width while computing natural height; do not pass the unconstrained sentinel for width. Every declared child participates in the parent snapshot, including a hidden button, so changes to an unused child can still cause a parent miss.

### Choose ownership

Composition does not dictate ownership. A screen-owned bundle is a useful default when reusable views should share results. In this example, `DocumentSizeCaches` retains the raw text and button caches plus the parent cache. Local bound handles connect the leaf caches to the parent and are captured by its calculation, without capturing the bundle or a view.

```swift
@MainActor
final class DocumentScreen: UIViewController {
    let sizeCaches = DocumentSizeCaches()
    private lazy var contentView = DocumentContentView(caches: sizeCaches)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(contentView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let available = view.bounds.inset(by: view.safeAreaInsets)
        let size = contentView.sizeThatFits(CGSize(
            width: max(0, available.width), height: CGFloat.greatestFiniteMagnitude
        ))
        contentView.frame = CGRect(origin: available.origin, size: size)
    }
}
```

Inside `DocumentContentView`, `sizeThatFits(_:)` calls `caches.contentSizes.size(of: self, toFit: size)`. Its `layoutSubviews()` calls the leaf caches with the corresponding controls and the same inner proposal, then assigns frames. The [complete bundle and view](Sources/DerivedKeysUIExample/DocumentContentView.swift) are compiled and tested together. They are application examples; no base class is required.

The view updates rendered text and line limits at initialization and model changes, and fonts at initialization and trait changes. Its control getters only read stored controls. The cache does not schedule layout or refit the container. The example's model setters schedule layout; the application remains responsible for refitting.

A view can instead own its own cache. An application can use a static cache when application-wide sharing is intentional. Separate instances own independent recipes and entries; assigning a cache reference shares its storage and recency. Keep configuration captured by a recipe fixed for its lifetime or select it as a dependency.

The cache retains its configured measurement closure. User captures and reference-valued dependencies can retain views or owners; entries do not retain lookup roots implicitly.

Bound lookup handles retain their original cache. Child descriptions retain only dependency readers, without retaining the cache, binding, or measurement closure. Capture the bound handles the calculation needs. See [storage, lifetime, and clearing](#storage-lifetime-and-clearing) for entry retention and removal.

### Nest layouts and map child roots

A composed cache can itself be a child. The [three-level card example](Examples/Size-Caches.md#nest-a-composed-layout) combines a header measurement with the document cache, adding a header-to-content gap. A card hit skips both; changing only the gap reuses their measurements. A parent with no local variable inputs can omit `dependingOn:` and derive its data dependencies entirely from its children.

For children with different root types, `bound(to:)` creates a measurement handle for a nonoptional key path, as shown above and in the [mapping example](Examples/Size-Caches.md#map-a-child-root). Bindings can be chained through further parents. They reuse the original cache and add no storage, key identity, or snapshot depth.

Use `at(_:)` when only a dependency description is needed; the parent calculation must call the original cache with the corresponding child root. Same-root and bound or mapped children can be mixed, and one child can be mapped to two distinct paths. Each binding reads its own path, so a title and subtitle are captured separately. The [composition limits](#composition-and-reentrancy) also apply to nested and mapped children.

### Use a custom measurement recipe

Use the closure initializer for proposal transforms, custom calculations, and authoritative model dependencies. For example, a parent-root cache can select `\.model.text` while measuring its synchronized text view. The [model-backed example](Examples/Size-Caches.md#select-authoritative-model-text) explains synchronization and the measured cost of reading text back from UIKit. Both initializers support zero selected dependencies; callers still own the completeness of the selected inputs.

## Install and import

Add `https://github.com/kylehughes/swift-derived-keys` in Xcode's package dependencies. Private checkouts require repository access. Use the development reference `main`:

```swift
.package(url: "https://github.com/kylehughes/swift-derived-keys", branch: "main")
```

For the short sizing API, add `.product(name: "DerivedKeysUI", package: "swift-derived-keys")` to your target and `import DerivedKeysUI` alongside UIKit. The package provides three library products:

| Product | Use |
| --- | --- |
| `DerivedKeysUI` | Key-path size recipes, typed child mappings, and recursive size caching. |
| `DerivedKeysUIKit` | Explicit fitting proposals and `LayoutCache` for caller-defined complete layout results such as sizes plus frames. |
| `DerivedKeys` | General-purpose keys, projections, snapshots, sources, and value-semantic memoization. |

### Compatibility

Requires Swift tools 6.4, Swift 6 language mode, and iOS 16.0+ or macOS 13.0+. Strict concurrency checking and warnings as errors apply to owned Swift targets. `SizeCache` reads and measures synchronously on the main actor. The closure initializer is also available on macOS; UIKit examples and tests are conditional on UIKit availability. The generic core uses only the Swift standard library and has no global-actor requirement. No macros or property wrappers are required.

## Use the cache correctly

### Dependencies and snapshots

Select every variable input that affects measurement, proposal transformation, branching, or combination. The API cannot discover undeclared closure captures. Key-path reads and measurement must see consistent state during the synchronous request, and dependency getters must not mutate result-relevant state or recursively evaluate caches. After a model change, the application must still schedule layout and refit its container as needed; see [view integration](#choose-ownership).

`Hashable` does not make a mutable reference a snapshot. Select immutable content, or expose a computed property that projects an immutable value and select that property by key path. The core's projection APIs are another escape hatch. Object identity or a document ID alone does not describe changing content. Keys retain complete values, concrete value types, and ordered child structure, so hash collisions do not substitute for equality.

### Fitting proposals

Both proposed dimensions must be finite and nonnegative. NaN, infinity, and negatives fail descriptive preconditions. `CGFloat.greatestFiniteMagnitude` is supported as the unbounded sentinel. Signed zero is normalized, and the calculation receives the same normalized proposal represented by the key; dimensions are not silently rounded. The facade leaves result sizing, rounding, and clamping to the recipe.

### Composition and reentrancy

Parents capture recursive dependency values even when child result storage is empty; cached sizes and child eviction state never become dependency identity. This is why clearing a child does not invalidate an otherwise valid parent result.

Dependency composition is immutable and acyclic by construction. The checked limit is 64 snapshot nodes per path: an empty description has depth one, a description with a selected value has depth two, and each parent adds a level. Mapping adds no level. Excess depth fails a precondition.

Reentering the same cache during its measurement, including count inspection or clearing, fails a precondition. Do not call a native-fitting cache from the measured view's own `sizeThatFits(_:)` override: a miss calls that override again. For that integration, supply a custom recipe that measures children or uses a separate uncached calculation. Wrapping a call to the same view's cached `sizeThatFits(_:)` in a closure still reenters the cache. Recursion through distinct child caches is supported, as in the [layout example](#compose-a-layout).

### Storage, lifetime, and clearing

`capacity` limits entries in each cache; zero disables storage. Choose it for the distinct content, fitting sizes, and other selected states you expect to revisit before eviction. Capacity counts entries, not bytes: large snapshots and results retain more memory. Successful lookups update LRU recency, and full caches evict their least recently used entry. Use `count`, `removeSize(of:toFit:)`, and `removeAll()` to inspect or clear local results. Removal selects the root's current dependencies and proposal. Bound handles expose measurement and dependency composition only; inspect or clear the original cache.

Clearing a parent leaves its children intact. Clearing or evicting a child leaves otherwise valid parent results intact. Previous input states can reuse retained entries when they return. If an undeclared external change requires clearing, clear **every affected result cache**, or represent that change as a dependency. There is no recursive clearing or shared eviction budget.

Entries retain snapshots and results, not lookup roots implicitly. The configured recipe and reference-valued dependencies can still retain objects; [choose ownership](#choose-ownership) with those captures in mind.

## Use the generic core

The same dependency selection and bounded reuse work without UI. This exporter captures text and an export option, so changing selection preserves the cached result:

```swift
import DerivedKeys

enum ExportOperation {}

struct Document {
    var text: String
    var isSelected: Bool
}

struct ExportInput: Hashable {
    let text: String
    let uppercase: Bool
}

struct Exporter {
    private var cache = MemoizationCache<
        RequestKey<ExportOperation, ExportInput, String>, String
    >(capacity: 32)

    mutating func export(_ document: Document, uppercase: Bool) -> String {
        let input = ExportInput(text: document.text, uppercase: uppercase)
        let key = RequestKey(
            operation: ExportOperation.self,
            dependencies: input,
            context: "plain-text"
        )
        return cache.value(for: key) {
            input.uppercase ? input.text.uppercased() : input.text
        }
    }
}

var exporter = Exporter()
var document = Document(text: "Hello", isSelected: false)
let first = exporter.export(document, uppercase: false)
document.isSelected = true
let second = exporter.export(document, uppercase: false) // Retained cache hit.
let capitals = exporter.export(document, uppercase: true) // Different key.
assert(first == second && capitals == "HELLO")
```

Changing text or the export option selects another entry; returning to earlier inputs can reuse a retained result. The [document export guide](Examples/Document-Export.md) describes the runnable example with ordered paragraphs and formats. Run it with `swift run DocumentExportExample`.

Use the [generic API guide](Examples/Generic-Core.md) for projections, typed operation keys, and runtime source graphs. `DependencySnapshot` also composes heterogeneous captured values directly. `MemoizationCache` supports throwing calculations without insertion on failure, treats a cached optional `nil` as a hit, and gives copied cache values independent storage behavior.

## Further documentation

| Task | Documentation |
| --- | --- |
| Map child roots or follow the complete ownership example | [Composing size caches](Examples/Size-Caches.md) |
| Look up the sizing API | [SizeCache reference](Documentation/DerivedKeysUI.docc/DerivedKeysUI.md) |
| Cache child frames as well as the overall size | [Explicit layout results](Examples/UI-Measurement.md) |
| Choose dependencies for a non-UI computation | [Core dependency design](Documentation/DerivedKeys.docc/DependencyDesign.md) |
| Evaluate cache costs | [Release benchmarks](Benchmarks/README.md), with workloads, measured results, and measurement limits |
| Build, test, or maintain the package | [Tests and maintenance](Documentation/Maintenance.md), including iOS 16 compiler checks, precondition probes, and Simulator execution |

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
