# Composing size caches

Use `DerivedKeysUI.SizeCache` to retain measurements selected by key-path dependencies. For a UIKit leaf, omit the closure to call the passed view's `sizeThatFits(_:)` on a miss. A parent declaring `children:` always supplies a calculation closure, as does any custom recipe.

Start with the [README](../README.md) for one measurement and a composed text/button layout. This guide covers mapped children, ownership, and dependency choices. The [complete application example](../Sources/DerivedKeysUIExample/DocumentContentView.swift) defines `DocumentContentView`, the screen-owned `DocumentSizeCaches` bundle, and a controller that assigns frames. These are application types; the library does not require them.

## Map a child root

A child can measure a nested root. Bind its cache to a path in the parent, then use that handle for both dependency capture and measurement. Here `titleSizing` and `subtitleSizing` are `SizeCacheBinding<PairView>` handles that share the original label cache. Each accepts the parent pair and follows its path to the corresponding label. Every label sharing this cache must use the same unselected measurement settings, fixed for the cache's lifetime:

```swift
import DerivedKeysUI
import UIKit

@MainActor
func makeTitleSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 128)
}

@MainActor
final class PairView: UIView {
    let title = UILabel()
    let subtitle = UILabel()
}

@MainActor
func makePairSizes(titleSizes: SizeCache<UILabel>) -> SizeCache<PairView> {
    let titleSizing = titleSizes.bound(to: \PairView.title)
    let subtitleSizing = titleSizes.bound(to: \PairView.subtitle)
    return SizeCache<PairView>(
        children: titleSizing, subtitleSizing,
        capacity: 128
    ) { pair, proposal in
        let titleSize = titleSizing.size(of: pair, toFit: proposal)
        let subtitleSize = subtitleSizing.size(of: pair, toFit: proposal)
        return CGSize(
            width: max(titleSize.width, subtitleSize.width),
            height: titleSize.height + subtitleSize.height
        )
    }
}
```

A title and subtitle with different selected values produce separate child requests through the same cache. Each binding reads its own path, so the title and subtitle are captured separately. Equal child inputs and proposals may intentionally reuse a result. Same-root children can appear alongside mapped children in one initializer.

A bound handle is a main-actor `SizeCacheBinding<Parent>` and can be chained with another `bound(to:)` to reach a further parent. It retains the original cache for measurement, with no additional storage, key identity, or snapshot depth. Inspect and clear that original cache; bindings have no count, capacity, or clearing API. Use a fully qualified key path such as `\PairView.title` when creating a standalone binding so Swift can infer the parent type.

Bindings and mappings do not unwrap optional roots. Arbitrary mapping closures and conditional child declarations are not supported. Map a nonoptional key path or keep the condition and any required stable projection in the parent recipe. Declared children are always captured, even if the calculation takes a branch that does not measure them. The facade does not discover caches called by a closure: list the children that determine the parent result and capture those same handles in its calculation.

## Nest a composed layout

A composed cache can itself be a child. Suppose an application's `DocumentCardView` holds a `headerLabel: UILabel`, a `contentView: DocumentContentView`, and a `spacing: CGFloat` gap. The card adds the header above the complete document. Its spacing is finite and nonnegative; each child follows its recipe's fixed-configuration contract.

```swift
@MainActor
func makeCardSizes(
    headerSizes: SizeCache<UILabel>,
    contentSizes: SizeCache<DocumentContentView>
) -> SizeCache<DocumentCardView> {
    let headerSizing = headerSizes.bound(to: \DocumentCardView.headerLabel)
    let contentSizing = contentSizes.bound(to: \DocumentCardView.contentView)
    return SizeCache<DocumentCardView>(
        dependingOn: \.spacing,
        children: headerSizing, contentSizing,
        capacity: 128
    ) { card, proposal in
        let childProposal = CGSize(
            width: proposal.width, height: CGFloat.greatestFiniteMagnitude
        )
        let headerSize = headerSizing.size(of: card, toFit: childProposal)
        let contentSize = contentSizing.size(of: card, toFit: childProposal)
        return CGSize(
            width: proposal.width,
            height: headerSize.height + card.spacing + contentSize.height
        )
    }
}
```

The screen constructs and retains the header, document, and card caches once. In its main-actor setup, `documentCaches` is a `DocumentSizeCaches` bundle and `card` is the view to measure:

```swift
let headerSizes = makeTitleSizes()
let cardSizes = makeCardSizes(headerSizes: headerSizes, contentSizes: documentCaches.contentSizes)
let cardSize = cardSizes.size(
    of: card, toFit: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
)
```

These are three levels: card, document, and document controls. A card hit skips the entire calculation. Changing only the card's spacing changes its height while reusing the header and document results. Changing document text selects new document and card entries while leaving the header reusable. The card expects an actual available width and computes natural height, just like the document. Frame assignment remains the application's responsibility.

The [compiler fixture](../Fixtures/iOS/READMEExamples.swift) includes the minimal card root and the complete calls. The root shown there is measurement scaffolding, not a package-owned view or a complete card layout implementation.

## Keep proposals with their calculations

The parent keys its own proposal and recursively captured dependency values. Child proposals do not enter the parent key; each child keys the proposal it receives at lookup. Padding, orientation, visibility, and other values used in transformation or combination belong in the parent selection. There is no need to declare the transformation twice.

The document example measures inner content at `max(0, outerWidth - 2 * padding)` and unconstrained height. Changing spacing changes only the parent key. Changing padding also changes the child's actual width. Changing the outer height changes the parent request even though this example chooses natural height; its unchanged child proposals can still hit.

Both proposal axes must be finite and nonnegative. `CGFloat.greatestFiniteMagnitude` denotes an unconstrained axis; infinity is rejected. Signed zero becomes positive zero in both key and callback proposal. Dimensions are not quantized. The recipe controls result sizing, including any rounding or clamping.

## Keep ownership explicit

The document screen owns a `DocumentSizeCaches` bundle and injects it into reusable views. The bundle's initializer retains the `UITextView` and `UIButton` caches as public properties and creates local bound handles for the parent. The parent declares and captures those same bindings. Its closure captures the children, not the bundle or a view.

Each cache has its own capacity and LRU order. Choose a capacity for the distinct content, widths, and other selected states likely to be revisited; capacity bounds entries, not the bytes retained by their snapshots and results. A view-owned cache and an intentionally static cache are equally valid; the package installs no global storage.

Descriptions retain dependency readers only, without retaining the cache, bound lookup handle, or measurement closure. The parent closure must retain any child handle it will call.

For dependency-only mapping, use `titleSizes.at(\PairView.title)` and call `titleSizes.size(of: pair.title, toFit: proposal)` in the calculation. Unlike a bound lookup handle, that descriptor does not retain the original cache, its measurement closure, or entries.

Cached entries contain captured values and `CGSize` results; the root supplied to `size(of:toFit:)` is not implicitly retained. Explicit user captures or reference-valued dependencies can still retain a root or owner.

`count` and `capacity` describe one cache. `removeSize(of:toFit:)` removes its entry for the current dependencies and normalized proposal; `removeAll()` clears only its storage. Parent and child results have independent eviction and clearing. Returning to a previous input may recover a retained result. Clearing after an undeclared external change must cover every affected cache; declaring that external input is usually easier to maintain.

## Capture stable values

A key path to a `Hashable` class can still return a mutable alias. Prefer a value snapshot, such as a computed `measurementContent` property returning immutable text and style data, and select `\.measurementContent`. Do not use a document ID alone to represent edits under the same ID. Use the core's explicit projections and snapshots for more complex value selection.

### Select authoritative model text

When the application already owns the displayed text, select that model property directly. In this example, `ArticleView.model` contains an ordinary `Article` value whose `text` is a `String`. Assigning or editing the model updates `textView.text` before the next size request:

```swift
@MainActor
func makeArticleTextSizes() -> SizeCache<ArticleView> {
    SizeCache<ArticleView>(
        dependingOn: \.model.text,
        \.textView.font,
        capacity: 256
    ) { view, proposal in
        view.textView.sizeThatFits(proposal)
    }
}
```

Retain the returned cache in the application's chosen owner, then call `textSizes.size(of: view, toFit: proposal)`. The [complete iOS 16 compiler fixture](../Fixtures/iOS/ModelTextExample.swift) includes the model, view, and an edit followed by another lookup. It fixes wrapping, text-container insets, padding, direction, and editing/scrolling settings; changing any of those requires another dependency. Font is selected explicitly. Model changes schedule layout, while the owner remains responsible for fitting and assigning the view's frame.

Equal strings can have different storage representations and hashing costs. In the [UIKit string measurements](../Benchmarks/String-Results.md), selecting native model text was substantially cheaper for repeated requests than reading identical text back from `UITextView`. Swift model storage is not a guarantee of contiguous UTF-8: a string assigned from UIKit can retain its representation. The package does not normalize strings automatically.

The model must remain authoritative and agree with the rendered content during measurement. If editing happens in the text view, synchronize the model before lookup or select the text view's current text. A stale model key can reuse an incorrect size. Full text remains a valid dependency; no content ID, revision, or custom wrapper is required.

### Consider a compact projection after measuring

If full-content hashing still dominates, an optional compact projection is the content's identity together with a reliable revision that changes on every size-relevant edit. Select those existing properties by key path; no wrapper is needed. Independent typography and layout inputs still need dependencies. A revision that misses an edit makes reuse incorrect. Do not reuse an identity/revision pair for different size-relevant content while affected entries may remain. The identity and revision must identify the same size-relevant content across all roots sharing the cache. Measure the full request and its hit rate before adopting this extra application contract; ordinary full-content dependencies remain the default. The [performance guide](../Benchmarks/README.md#choosing-dependencies-for-an-application) provides the measured comparison.

## Inspect snapshots and composition limits

Selection and calculation are synchronous on the main actor. Keep selected values and any other result-relevant state consistent throughout the request. Dependency getters must read values without mutation, I/O, or recursive evaluation.

A hit still reads all declared dependencies and hashes and compares their full snapshots, but does not invoke measurements or consult child result storage. `snapshot(of:)` exposes the dependency snapshot for inspection; it excludes proposal and recipe identity and is not a complete result key on its own.

Public construction cannot create a cycle in the immutable graph. Its limit is 64 snapshot nodes per path, counting value leaves and composition boundaries. Mapping adds no boundary. An empty cache has depth one; a cache selecting a property has depth two; a parent adds one. Excess depth fails a descriptive precondition. Same-cache measurement reentry, including result inspection/removal through an alias, also fails a precondition; nesting different caches is supported.

## Integrate with UIKit layout

Changing content, scheduling a UIKit layout pass, asking for another size, and assigning the outer frame remain separate application actions. The document example synchronizes text and line limits at initialization and model changes, and category-only fonts at initialization and trait changes. Its control getters do not configure the controls. It schedules layout when content or category changes. The controller remains responsible for refitting and assigning the container frame.

A native-fitting cache calls the passed view's `sizeThatFits(_:)` on a miss. Calling that same cache from that view's override reenters the cache and fails a precondition. Use a closure recipe that measures children or calls a separate uncached calculation. A closure that calls the same view's cached `sizeThatFits(_:)` still reenters the cache. The convenience initializer does not infer dependencies or make mutable `Hashable` aliases stable.

## Choose a lower-level result API

Use `DerivedKeysUIKit.LayoutCache` when you want to cache an application-defined result containing complete child frames as well as overall size. Its [frame-layout guide](UI-Measurement.md) shows that explicit-input API. Use the [generic core](Generic-Core.md) for other computations, throwing calculations, typed operation keys, or nonisolated ownership.
