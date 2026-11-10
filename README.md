# DerivedKeys

[![Provenance: Software Factory](https://img.shields.io/badge/Provenance-Software_Factory-007AFF)](#provenance)
[![Platform Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkylehughes%2Fswift-derived-keys%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/kylehughes/swift-derived-keys)
[![Test](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml/badge.svg)](https://github.com/kylehughes/swift-derived-keys/actions/workflows/ci.yml)

DerivedKeys memoizes Swift calculations: it reuses a recipe's result when the values you select match a retained entry. With `DerivedKeysUI`, you cache a view's fitted size by listing the key paths that affect layout, then compose child caches to reuse a parent view's size. The key-building and caching APIs underneath also work on their own, with no UI.

[Cache one measurement](#cache-one-measurement) · [Install](#install) · [Compose a layout](#compose-a-layout) · [Generic core](#use-the-generic-core) · [Further documentation](#further-documentation)

## Cache one measurement

Create caches once on the main actor and retain them across layout passes. For a `UIView`, the UIKit initializer calls `sizeThatFits(_:)` on a cache miss. List every property that can change the measured size.

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

`size(of:toFit:)` takes the **root** view to measure and the fitting **proposal** you would pass to `sizeThatFits(_:)`. A lookup reads the selected `Hashable` values and automatically includes **both fitting dimensions** in the key. The root itself is not part of the key and need not be `Hashable` or `Sendable`, so identically configured views share cached sizes. A hit skips the recipe.

A cache is only as accurate as the selection you give it. The [cache contract](Documentation/DerivedKeysUI.docc/CacheContract.md) states the rules once:

- [Select every variable input](Documentation/DerivedKeysUI.docc/CacheContract.md#select-every-variable-input); any setting you leave out must stay fixed for the cache's lifetime and match across every view sharing the cache.
- [Select stable values](Documentation/DerivedKeysUI.docc/CacheContract.md#select-stable-values); a mutable `Hashable` reference type is not a snapshot.
- [Know what a cache retains](Documentation/DerivedKeysUI.docc/CacheContract.md#what-a-cache-retains) and [what counts as reentry](Documentation/DerivedKeysUI.docc/CacheContract.md#reentrancy).
- [Fitting proposals](Documentation/DerivedKeysUI.docc/CacheContract.md#fitting-proposals): `CGFloat.greatestFiniteMagnitude` and `.infinity` both mean an unconstrained axis; NaN, `-infinity`, and negative values fail.

If your model already holds the displayed text, [select that model property](Examples/Size-Caches.md#select-authoritative-model-text) and keep the view synchronized; reading a native Swift string is often faster than reading bridged text back from `UITextView`.

## Install

Add `https://github.com/kylehughes/swift-derived-keys` in Xcode's package dependencies, starting at version `1.0.0`, or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/kylehughes/swift-derived-keys", from: "1.0.0")
```

Add the product you need to your target, for example `.product(name: "DerivedKeysUI", package: "swift-derived-keys")`, and import it alongside UIKit.

| Product | Use |
| --- | --- |
| `DerivedKeysUI` | `SizeCache` and child bindings for view sizing, `LayoutCache` and fitting proposals for complete layout results, and `MainActorResultCache` for other main-actor results. |
| `DerivedKeys` | `ResultCache`, general-purpose keys and projections, and value-semantic memoization using only the Swift standard library. |

### Compatibility

- **Swift:** 6.4+ (Swift 6 language mode)
- **iOS:** 16.0+
- **macOS:** 13.0+
- **Xcode:** 27.1 (tested)

## When caching pays off

A cache hit still reads the selected values, builds a snapshot, and hashes and compares the key. For an already-warm `UILabel`, that work costs at least as much as calling UIKit directly—in the recorded Simulator runs ([native fitting](Benchmarks/UIKit-Native-Fitting-Results.md), [specialization](Benchmarks/Specialization-Results.md)), warm labels were faster uncached. Caching paid off for composed parent views, `UITextView` measurements, and sizes shared across many views. If a single view only needs to remember its most recent size, a stored `CGSize` may be enough. Use the [benchmark methodology](Benchmarks/README.md) to measure your own workload.

## Compose a layout

To cache a parent view, bind each child cache to its key path on the parent and list those bindings in `children:`. Then call those same bindings inside the parent's recipe.

Here `textSizing` and `buttonSizing` are `SizeCacheBinding<DocumentContentView>` bindings. They read child dependencies and look up sizes through the original leaf caches, taking the parent `DocumentContentView` as their root:

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

The recipe captures the same bindings declared in `children:`. A parent hit skips the recipe and every child lookup. On a parent miss, the recipe runs and each child lookup can still hit its own cache.

Proposal math stays inside the recipe. Because `padding` narrows the width passed to the children, `\.padding` belongs in the parent's selection; each child keys the proposal it actually receives. This layout fills a finite available width and returns natural height, so do not pass `greatestFiniteMagnitude` for width.

Every child listed in `children:` contributes its selected values to the parent's key, even when a branch in the recipe skips measuring it. Changing a hidden button's title or font therefore causes a parent miss. In debug builds, measuring through a size cache that is not declared in `children:` fails an assertion, because parent hits would ignore that child's inputs. A parent that measures a fixed captured root can pass `allowsUndeclaredMeasurements: true`. See [declare children](Documentation/DerivedKeysUI.docc/CacheContract.md#declare-children).

### Nest layouts and map child roots

A composed cache can itself be a child of another parent cache. The [three-level card example](Examples/Size-Caches.md#nest-a-composed-layout) combines a header label cache with `contentSizes`; a card hit skips both, and changing only the card's spacing reuses their cached sizes. A parent with no variable inputs of its own can omit `dependingOn:`.

`bound(to:)` is the only way to map a child cache onto a parent root. It takes a nonoptional key path, can be chained through deeper view hierarchies, and adds no storage or snapshot depth. The [mapping example](Examples/Size-Caches.md#map-a-child-root) shows two labels on one parent sharing a single `SizeCache<UILabel>`.

### Use a custom measurement recipe

Use the closure initializer whenever you need proposal transforms, custom sizing math, or authoritative model dependencies. For example, a cache rooted on a container view can select `\.model.text` while measuring its synchronized text view; see the [model-backed example](Examples/Size-Caches.md#select-authoritative-model-text). The closure initializer also works on macOS, whereas the convenience `UIView` initializer requires UIKit.

## Choose ownership

Composition does not dictate who owns a cache. A screen-owned bundle works well when reusable views should share cached sizes. In the example below, `DocumentSizeCaches` holds the leaf text and button caches alongside the composed parent cache. Local bindings connect the leaf caches to the parent and are captured by the parent's recipe, without capturing the bundle or any view.

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

Inside `DocumentContentView`, `sizeThatFits(_:)` calls `caches.contentSizes.size(of: self, toFit: size)`. Its `layoutSubviews()` queries the leaf caches with the subviews and the same inner proposal, then assigns their frames. The [complete bundle and view](Sources/DerivedKeysUIExample/DocumentContentView.swift) are compiled and tested together as ordinary application types—no library base class is required.

The view updates its controls before measurement: text and line limits at initialization and when the model changes, and fonts at initialization and on trait changes. Model setters call `setNeedsLayout()`, and the view controller refits and assigns the outer frame. A cache never observes state or schedules layout.

You can also store a cache on an individual view or in an intentionally shared static property. Each `SizeCache` owns its recipe and entries, and sharing the reference shares storage and recency order. Because a cache retains its recipe, avoid strongly capturing the cache's owner. See the [cache contract](Documentation/DerivedKeysUI.docc/CacheContract.md#capacity-eviction-and-clearing) for retention, capacity, and clearing rules.

## Use the generic core

The `DerivedKeys` module depends only on the Swift standard library. `ResultCache` binds selected key paths and a recipe once. Here it tokenizes a document's text, so toggling selection reuses the cached token array:

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

`ResultCache` is a value type: copying it produces independent entries. Its recipe is synchronous and nonthrowing, and neither the root input nor the result needs to be `Hashable` or `Sendable`. Because it takes ordinary key paths and closures and is not `Sendable`, a main-actor type can own one directly and Swift 6 region isolation keeps it confined there. Use `MainActorResultCache` from `DerivedKeysUI` when you want a shared main-actor reference. The [result-cache guide](Examples/Result-Caches.md) compares the two and shows how a plain-text row caches its rendered line count, then feeds that count into a `SizeCache` for `sizeThatFits(_:)`.

For explicit projections, typed operation keys, and runtime source graphs, see the [generic API guide](Examples/Generic-Core.md). `DependencySnapshot` composes heterogeneous captured values directly, and `MemoizationCache` supports throwing calculations without inserting on failure. The [document export guide](Examples/Document-Export.md) demonstrates these lower-level APIs in a runnable target (`swift run DocumentExportExample`).

## Further documentation

| Task | Documentation |
| --- | --- |
| Check the rules every cache relies on | [Cache contract](Documentation/DerivedKeysUI.docc/CacheContract.md) |
| Map child roots or follow the complete ownership example | [Composing size caches](Examples/Size-Caches.md) |
| Look up the sizing API | [DerivedKeysUI reference](Documentation/DerivedKeysUI.docc/DerivedKeysUI.md) |
| Cache other results or pass a result to another cache | [Configured result caches](Examples/Result-Caches.md) |
| Cache child frames as well as the overall size | [Explicit layout results](Examples/UI-Measurement.md) |
| Choose dependencies for a non-UI computation | [Core dependency design](Documentation/DerivedKeys.docc/DependencyDesign.md) |
| Evaluate cache costs | [Release benchmarks](Benchmarks/README.md), with workloads, measured results, and measurement limits |
| Build, test, or maintain the package | [Tests and maintenance](Documentation/Maintenance.md) |

## Contributions

DerivedKeys is not accepting source contributions at this time. Bug reports will be considered.

## Provenance

DerivedKeys was implemented from Kyle Hughes' technical specification using the Swift Package Factory workflow and Codex.

## "Author"

[Kyle Hughes](https://kylehugh.es)

[![Bluesky](https://img.shields.io/badge/Bluesky-0285FF?logo=bluesky&logoColor=fff)](https://bsky.app/profile/kylehugh.es)<br>
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?logo=linkedin&logoColor=fff)](https://www.linkedin.com/in/kyle-hughes)<br>
[![Mastodon](https://img.shields.io/mastodon/follow/109356914477272810?domain=https%3A%2F%2Fmister.computer&style=social)](https://mister.computer/@kyle)

## License

DerivedKeys is available under the [MIT License](LICENSE).
