# DerivedKeys

[![Provenance: Software Factory](https://img.shields.io/badge/Provenance-Software_Factory-007AFF)](#provenance)
[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Test](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml/badge.svg)](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml)

DerivedKeys provides **memoization** for Swift: reusing a calculation's result when the inputs you select match a cached entry. With `DerivedKeysUI`, you cache a view's fitted size by listing the key paths that affect layout, then compose child caches to reuse a parent view's size. The underlying key-building APIs also work independently of the caches.

Use `DerivedKeysUI` for view sizing. For computations without UI, start with the [generic core](#use-the-generic-core).

[Sizing walkthrough](#sizing-views) · [Installation and products](#install-and-import) · [Cache rules](#use-the-cache-correctly) · [Documentation and maintenance](#further-documentation)

## Sizing views

Create your caches once on the main actor and retain them across layout passes. This walkthrough caches a single control's size, combines two child caches into a parent layout, and [injects the caches into a view](#choose-ownership).

### Cache one measurement

For a leaf `UIView`, the UIKit convenience initializer calls `sizeThatFits(_:)` on a cache miss. List every property that can change the measured size. Any size-affecting properties you omit must stay fixed for the cache's lifetime and match across every view sharing it. If a setting varies, include its key path or use a separate cache.

Here `view` is an application `DocumentContentView` exposing its text view and button. The [complete example](Sources/DerivedKeysUIExample/DocumentContentView.swift) keeps the text view's wrapping, insets, line-fragment padding, and scrolling settings fixed.

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

`size(of:toFit:)` takes the **root** view to measure and the fitting **proposal** you would pass to `sizeThatFits(_:)`. A lookup reads the selected `Hashable` values and automatically includes **both fitting dimensions** in the key. Those values must stay stable while cached. The root is not implicitly part of the key and need not be `Hashable` or `Sendable`, so equivalently configured views can share results.

Use finite, nonnegative proposal dimensions; `CGFloat.greatestFiniteMagnitude` marks an unconstrained axis. The cache normalizes the proposal before measurement; see [fitting proposals](#fitting-proposals) for the rules. A hit skips the measurement closure, so side effects that must happen on every request belong outside it.

If your model already holds the displayed text, consider [selecting that model property](Examples/Size-Caches.md#select-authoritative-model-text) and keeping the view synchronized. In the recorded Simulator workload, native model strings made repeated requests cheaper than identical text read back from UIKit. The guide explains the storage differences; a `String` property's type alone does not guarantee cheaper hashing.

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

The button's remaining measurement settings stay fixed, including its configuration. The closure captures the same bound handles declared in `children:`. A parent hit skips the closure and all child result lookups. On a parent miss, the closure runs and each child lookup can hit its own cache independently.

Proposal math lives in the closure. Because padding changes the children's inner width, `\.padding` belongs in the parent's dependencies; each child keys the actual proposal it receives. This layout expects an available width and returns that width while computing natural height, so do not pass `greatestFiniteMagnitude` for width.

Every child listed in `children:` contributes its selected dependency values to the parent snapshot, even when a branch skips measuring it. Changing a hidden button's title or font can therefore cause a parent miss.

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

`DocumentContentView` updates its controls before measurement: text and line limits at initialization and model changes, and fonts at initialization and trait changes. Its getters only read stored controls. Model setters call `setNeedsLayout()`, while the controller remains responsible for refitting and assigning the outer frame. The cache itself does not schedule layout.

You can also store a cache on an individual view or in an intentionally shared static property. Each `SizeCache` instance owns its measurement closure and entries; passing the reference around shares its storage and recency order. Keep configuration captured by the closure fixed for its lifetime or select it as a dependency.

A binding retains its original cache, but passing it in `children:` retains only its dependency readers. The parent's closure must capture the handles it calls. Caches retain their configured closures, so avoid a strong capture of an owner that would create a cycle. Selected reference values can also retain objects; entries do not implicitly retain the root passed to lookup. See [storage, lifetime, and clearing](#storage-lifetime-and-clearing) for details.

### Nest layouts and map child roots

A composed cache can itself be a child. The [three-level card example](Examples/Size-Caches.md#nest-a-composed-layout) combines a header measurement with the document cache, adding a header-to-content gap. A card hit skips both; changing only the gap reuses their measurements. A parent with no local variable inputs can omit `dependingOn:` and derive its data dependencies entirely from its children.

For children with different root types, `bound(to:)` creates a measurement handle for a nonoptional key path, as shown above and in the [mapping example](Examples/Size-Caches.md#map-a-child-root). Bindings can be chained through further parents. They reuse the original cache and add no storage, key identity, or snapshot depth.

Use `at(_:)` when you only need a dependency description. In the calculation, call the original cache with the child root from that same path. You can combine same-root, bound, and mapped children, or map one child cache to two distinct paths. Each binding reads its own path, so a title and subtitle are captured separately. The [composition limits](#composition-and-reentrancy) also apply to nested and mapped children.

### Use a custom measurement recipe

Use the closure initializer for proposal transforms, custom calculations, and authoritative model dependencies. For example, a parent-root cache can select `\.model.text` while measuring its synchronized text view. The [model-backed example](Examples/Size-Caches.md#select-authoritative-model-text) explains synchronization and the measured cost of reading text back from UIKit. Both initializers support zero selected dependencies; callers still own the completeness of the selected inputs.

The closure initializer is also available on macOS; native `UIView` fitting requires UIKit.

## Install and import

Add `https://github.com/kylehughes/swift-derived-keys` in Xcode's package dependencies, starting at version `1.0.0`, or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/kylehughes/swift-derived-keys", from: "1.0.0")
```

For the short sizing API, add `.product(name: "DerivedKeysUI", package: "swift-derived-keys")` to your target and `import DerivedKeysUI` alongside UIKit. The package provides three library products:

| Product | Use |
| --- | --- |
| `DerivedKeysUI` | Key-path size recipes, recursive size caching, and `MainActorResultCache` for other results. |
| `DerivedKeysUIKit` | Explicit fitting proposals and `LayoutCache` for caller-defined complete layout results such as sizes plus frames. |
| `DerivedKeys` | `ResultCache`, general-purpose keys and projections, and value-semantic memoization. |

### Compatibility

- **Swift:** 6.4+ (Swift 6 language mode)
- **iOS:** 16.0+
- **macOS:** 13.0+
- **Xcode:** 27.1 (tested)

## Use the cache correctly

### Dependencies and snapshots

Select every variable input that affects measurement, proposal transformation, branching, or combination. The API cannot discover undeclared closure captures. Key-path reads and measurement must see consistent state during the synchronous request, and dependency getters must not mutate result-relevant state or recursively evaluate caches. After a model change, the application must still schedule layout and refit its container as needed; see [view integration](#choose-ownership).

`Hashable` does not make a mutable reference a snapshot. Select immutable content, or expose a computed property that projects an immutable value and select that property by key path. The core's projection APIs are another escape hatch. Object identity or a document ID alone does not describe changing content. Keys retain complete values, concrete value types, and ordered child structure, so hash collisions do not substitute for equality.

### Fitting proposals

Both proposed dimensions must be finite and nonnegative. NaN, infinity, and negatives fail descriptive preconditions. `CGFloat.greatestFiniteMagnitude` is supported as the unbounded sentinel. Signed zero is normalized, and the calculation receives the same normalized proposal represented by the key; dimensions are not silently rounded. The facade leaves result sizing, rounding, and clamping to the recipe.

### Composition and reentrancy

A parent captures its children's dependency values recursively, even when a child cache is empty. Child sizes and eviction state never enter the parent key, so clearing a child does not invalidate an otherwise valid parent entry.

Dependency composition is immutable and acyclic by construction. The checked limit is 64 snapshot nodes per path: an empty description has depth one, a description with a selected value has depth two, and each parent adds a level. Mapping adds no level. Excess depth fails a precondition.

Reentering the same cache while it measures, including reading `count` or removing entries, fails a precondition. The UIKit convenience initializer calls the view's `sizeThatFits(_:)` on a miss, so calling that cache from the same view's override recurses back into the cache. To cache a custom view's `sizeThatFits(_:)`, use a closure that measures children or calls a separate uncached helper. Calling the same cached override from inside that closure would still reenter the cache. Calls through distinct child caches are supported, as in the [layout example](#compose-a-layout).

### Storage, lifetime, and clearing

`capacity` limits entries in each cache; zero disables storage. Choose it for the distinct content, fitting sizes, and other selected states you expect to revisit before eviction. Capacity counts entries, not bytes: large snapshots and results retain more memory. Successful lookups update LRU recency, and full caches evict their least recently used entry. Use `count`, `removeSize(of:toFit:)`, and `removeAll()` to inspect or clear local results. Removal selects the root's current dependencies and proposal. Bound handles expose measurement and dependency composition only; inspect or clear the original cache.

Clearing a parent leaves its children intact. Clearing or evicting a child leaves otherwise valid parent results intact. Previous input states can reuse retained entries when they return. If an undeclared external change requires clearing, clear **every affected result cache**, or represent that change as a dependency. There is no recursive clearing or shared eviction budget.

Entries retain snapshots and results, not lookup roots implicitly. The configured recipe and reference-valued dependencies can still retain objects; [choose ownership](#choose-ownership) with those captures in mind.

### Check whether caching pays off

A hit still reads dependencies, builds a snapshot, and hashes and compares it. For a small view that only needs its last size, a request struct and stored `CGSize` may suffice. These APIs let you compose dependencies and retain several input states within a fixed capacity.

In the [recorded Simulator run](Benchmarks/UIKit-Native-Fitting-Results.md), warm composed parents and some shared measurements benefited; already-warm labels and the low-hit mixed parent trace were faster with direct UIKit fitting. Use the [benchmark methodology](Benchmarks/README.md) to evaluate your own workload.

## Use the generic core

The `DerivedKeys` core uses only the Swift standard library and has no global-actor requirement. `ResultCache` binds selected key paths and a calculation once. This cache tokenizes a model's text; changing selection leaves its cached result available:

```swift
import DerivedKeys

struct SearchDocument {
    var text: String
    var isSelected: Bool
}

var tokens = ResultCache<SearchDocument, [String]>(
    dependingOn: \.text,
    capacity: 128
) { document in
    document.text.split(whereSeparator: \.isWhitespace).map(String.init)
}

var document = SearchDocument(text: "Shared cache results", isSelected: false)
let first = tokens.value(for: document)
document.isSelected = true
let second = tokens.value(for: document) // Reuses the first result.
assert(first == second)
```

`ResultCache` is a value type: copying it gives independent entry mutation. Its calculation is synchronous and nonthrowing; inputs and results need not be `Hashable` or `Sendable`. Select every variable input the calculation reads, and keep selected values stable while stored.

For main-actor recipes, use `MainActorResultCache` from `DerivedKeysUI`. The [result-cache guide](Examples/Result-Caches.md) shows how a plain-text row can cache its rendered line count by text, width, and font, then use that count and the remaining layout inputs to cache the view's `sizeThatFits(_:)` result.

Use the [generic API guide](Examples/Generic-Core.md) for projections, typed operation keys, and runtime source graphs. `DependencySnapshot` composes heterogeneous captured values directly. `MemoizationCache` supports throwing calculations without insertion on failure, treats a cached optional `nil` as a hit, and gives copied cache values independent storage behavior. The [document export guide](Examples/Document-Export.md) demonstrates these lower-level APIs; run it with `swift run DocumentExportExample`.

## Further documentation

| Task | Documentation |
| --- | --- |
| Map child roots or follow the complete ownership example | [Composing size caches](Examples/Size-Caches.md) |
| Look up the sizing API | [SizeCache reference](Documentation/DerivedKeysUI.docc/DerivedKeysUI.md) |
| Cache other results or pass a result to another cache | [Configured result caches](Examples/Result-Caches.md) |
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
