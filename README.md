# DerivedKeys

[![Provenance: Software Factory](https://img.shields.io/badge/Provenance-Software_Factory-007AFF)](#provenance)
[![Swift tools: 6.4](https://img.shields.io/badge/Swift_tools-6.4-F05138)](Package.swift)
[![macOS minimum: 13+](https://img.shields.io/badge/macOS-13%2B-007AFF)](#compatibility)
[![iOS minimum: 16+](https://img.shields.io/badge/iOS-16%2B-007AFF)](#compatibility)

DerivedKeys builds cache keys from the values a computation depends on. Its sizing API lets you cache a view's size by declaring the properties that affect layout, then compose child caches to cache an entire layout. The underlying keys and bounded memoization are general-purpose Swift APIs.

Use `DerivedKeysUI` for sizing; see [installation](#install-and-import). Create caches once in a retained main-actor owner.

## Cache one measurement

`DocumentContentView` below is an application type. Its `content` is a stable `Hashable` value—in the [complete example](Sources/DerivedKeysUIExample/DocumentContentView.swift), a `String`. `isExpanded` controls the line limit. The example fixes typography rules and the button title, and explicitly selects Dynamic Type. Additional variable measurement inputs need additional dependencies.

```swift
import DerivedKeysUI
import UIKit

let textSizes = SizeCache<DocumentContentView>(
    dependingOn: \.content,
    \.isExpanded,
    \.traitCollection.preferredContentSizeCategory,
    capacity: 256
) { view, proposal in
    view.textView.sizeThatFits(proposal)
}

let size = textSizes.size(of: view, toFit: availableSize)
```

The initializer binds the selected properties and measurement recipe. A lookup reads their current values and automatically includes **both fitting dimensions** in the key. It returns a retained result when that complete request matches. The root view is not part of the key, so different views can reuse a result through the same cache. Neither the view nor its properties need to be `Sendable`; selected values must be `Hashable` and stable.

## Compose a layout

Add a button measurement, then declare both children when constructing the parent:

```swift
let buttonSizes = SizeCache<DocumentContentView>(
    dependingOn: \.traitCollection.preferredContentSizeCategory,
    capacity: 256
) { view, proposal in
    view.button.sizeThatFits(proposal)
}

let contentSizes = SizeCache<DocumentContentView>(
    dependingOn: \.padding,
    \.spacing,
    \.showsButton,
    children: textSizes, buttonSizes,
    capacity: 256
) { view, proposal in
    let innerProposal = CGSize(
        width: max(0, proposal.width - 2 * view.padding),
        height: CGFloat.greatestFiniteMagnitude
    )
    let text = textSizes.size(of: view, toFit: innerProposal)
    let button = view.showsButton
        ? buttonSizes.size(of: view, toFit: innerProposal)
        : .zero
    return CGSize(
        width: proposal.width,
        height: 2 * view.padding + text.height + button.height
            + (view.showsButton ? view.spacing : 0)
    )
}

let initial = contentSizes.size(of: view, toFit: availableSize)
view.spacing += 4
let spaced = contentSizes.size(of: view, toFit: availableSize) // Parent miss; children hit.
view.content += " Another paragraph."
let edited = contentSizes.size(of: view, toFit: availableSize) // Parent and text miss; button hits.
```

The calculation captures the same child handles declared in `children:`. A parent hit skips its calculation and all child result lookups. A parent miss executes the calculation, whose child lookups can independently hit. Parents capture recursive dependency values even when child result storage is empty; cached sizes and child eviction state never become dependency identity.

Proposal transformation appears only in the calculation. Padding affects the inner width, so padding belongs in the parent's dependencies; each child keys the actual proposal it receives. The example intentionally computes natural height from the outer width. Every declared child participates in the parent snapshot, including a hidden button, so unused-child changes may conservatively cause a parent miss.

Parents can themselves be children, and caches with no explicit properties can depend entirely on children:

```swift
let outerSizes = SizeCache<DocumentContentView>(
    children: contentSizes,
    capacity: 256
) { view, proposal in
    contentSizes.size(of: view, toFit: proposal)
}
```

For children with different root types, use `at(_:)` with a key path to the child's root, as shown in the [mapping example](Examples/Size-Caches.md#map-a-child-root). This maps a dependency description, without creating a cache or copying entries. The calculation calls each original cache with that same mapped root. Same-root and mapped children can be mixed, and one child can be mapped to two distinct paths.

## Choose ownership

Composition does not dictate ownership. A screen-owned bundle is a useful default when reusable views should share results. The example's application-owned `DocumentSizeCaches` constructs the two children once, constructs the parent using those same handles, and retains all three. Parent closures capture child handles rather than the bundle or a view.

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

Inside `DocumentContentView`, `sizeThatFits(_:)` calls `caches.contentSizes.size(of: self, toFit: size)`. Its `layoutSubviews()` calls the retained child handles with the same inner proposal and assigns frames. The [complete bundle and view](Sources/DerivedKeysUIExample/DocumentContentView.swift) are compiled and tested together; they are application examples, not required base classes. The controls synchronize rendered text, line limits, and category-only fonts from the declared values before direct measurement.

A view can instead own its own cache. An application can use a static cache when application-wide sharing is intentional. Separate instances own independent recipes and entries; assigning a cache reference shares its storage and recency. Keep configuration captured by a recipe fixed for its lifetime or select it as a dependency.

## Install and import

Add `https://github.com/kylehughes/swift-derived-keys` in Xcode's package dependencies. Repository access is required. Use the development reference `main`:

```swift
.package(url: "https://github.com/kylehughes/swift-derived-keys", branch: "main")
```

For the short sizing API, add `.product(name: "DerivedKeysUI", package: "swift-derived-keys")` to your target and `import DerivedKeysUI` alongside UIKit. Existing products remain available:

| Product | Use |
| --- | --- |
| `DerivedKeysUI` | Key-path size recipes, typed child mappings, and recursive size caching. |
| `DerivedKeysUIKit` | Explicit fitting proposals and `LayoutCache` for caller-defined complete layout results such as sizes plus frames. |
| `DerivedKeys` | General-purpose keys, projections, snapshots, sources, and value-semantic memoization. |

### Compatibility

Requires Swift tools 6.4, Swift 6 language mode, and iOS 16.0+ or macOS 13.0+. Strict concurrency checking and warnings as errors apply to owned Swift targets. `SizeCache` reads and measures synchronously on the main actor. Its geometry support also builds on macOS; UIKit examples and tests are conditional on UIKit availability. The generic core uses only the Swift standard library and has no global-actor requirement. No macros or property wrappers are required.

## Use the cache correctly

Select every variable input that affects measurement, proposal transformation, branching, or combination. The API cannot discover undeclared closure captures. Key-path reads and measurement must see consistent state during the synchronous request, and dependency getters must not mutate result-relevant state or recursively evaluate caches. Changing a model does not automatically schedule layout or refit its container.

`Hashable` does not make a mutable reference a snapshot. Select immutable content, or expose a computed property that projects an immutable value and select that property by key path. The core's projection APIs are another escape hatch. Object identity or a document ID alone does not describe changing content. Keys retain complete values, concrete value types, and ordered child structure, so hash collisions do not substitute for equality.

Both proposed dimensions must be finite and nonnegative. NaN, infinity, and negatives fail descriptive preconditions. `CGFloat.greatestFiniteMagnitude` is supported as the unbounded sentinel. Signed zero is normalized, and the calculation receives the same normalized proposal represented by the key; dimensions are not silently rounded. The facade leaves result sizing, rounding, and clamping to the recipe.

Dependency composition is immutable and acyclic by construction. The checked limit is 64 snapshot nodes per path: an empty description has depth one, a description with a selected value has depth two, and each parent adds a level. Mapping adds no level. Excess depth fails a precondition. Each declared occurrence is read independently, including repeated mappings, so separate root bindings cannot accidentally share a traversal snapshot. Reentering the same cache during its measurement, including count inspection or clearing, fails a precondition; recursion through distinct child caches is supported.

### Storage, lifetime, and clearing

`capacity` limits entries in each cache; zero disables storage. Successful lookups update LRU recency, and full caches evict their least recently used entry. Use `count`, `removeSize(of:toFit:)`, and `removeAll()` to inspect or clear local results. Removal selects the root's current dependencies and proposal.

Clearing a parent leaves its children intact. Clearing or evicting a child leaves otherwise valid parent results intact. Previous input states can reuse retained entries when they return. If an undeclared external change requires clearing, clear **every affected result cache**, or represent that change as a dependency. There is no recursive clearing or shared eviction budget.

Entries retain snapshots and results, not lookup roots implicitly. The facade retains its configured measurement closure; user captures and reference-valued dependencies can retain objects. Child descriptions retain dependency-reading recipes, not child result storage. Keep the child handles needed by a calculation in that calculation's captures. Side effects that must run on every request belong outside the cached recipe.

## Use the generic core

The same dependency and memoization concepts work without UI. The [document exporter](Examples/Document-Export.md) selects content and export options while ignoring selection and scrolling; run it with `swift run DocumentExportExample`.

Use the [generic API guide](Examples/Generic-Core.md) for typed keys, `KeyProjection`, `KeySource`, and `MemoizationCache`. `DependencySnapshot(value:)` and `DependencySnapshot(children:)` also support direct heterogeneous value composition outside UI. The original throwing construction and computation APIs, optional-value hits, and independent value copies remain available.

For a small view with one remembered size, an ordinary request struct and stored result may suffice. These APIs provide declared dependency composition and bounded reuse across several input states. Caching still pays for snapshot selection, hashing, and equality; it is not universally faster than direct measurement.

## Further documentation

- [Sizing and mapped children](Examples/Size-Caches.md), including the complete ownership example.
- [SizeCache API](Documentation/DerivedKeysUI.docc/DerivedKeysUI.md), [explicit layout results](Examples/UI-Measurement.md), and [core dependency design](Documentation/DerivedKeys.docc/DependencyDesign.md).
- [Release benchmarks](Benchmarks/README.md), with workloads, measured results, and allocation limits.
- [Tests and maintenance](Documentation/Maintenance.md), including explicit iOS 16 compiler checks, precondition probes, and Simulator execution.

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
