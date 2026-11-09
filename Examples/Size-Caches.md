# Composing size caches

`SizeCache` caches `CGSize` measurements keyed by selected key paths and the fitting proposal. For a `UIView` leaf, the UIKit initializer calls the root view's `sizeThatFits(_:)` on a miss. When you compose `children:` or need custom measurement logic, you supply a recipe closure.

Start with the [README](../README.md) for a single-view measurement and a two-child layout. This guide covers child bindings, child declarations, multi-level nesting, proposal transforms, ownership, and model-backed text. The [complete application example](../Sources/DerivedKeysUIExample/DocumentContentView.swift) defines `DocumentContentView`, the screen-owned `DocumentSizeCaches` bundle, and a view controller that assigns frames—all ordinary application types, with no required base class. For the rules every cache shares, see the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md).

## Map a child root

When a child cache measures a subview or nested value, call `bound(to:)` with a key path from the parent root to the child root. Pass the resulting binding in `children:` and call it inside the parent's recipe; `bound(to:)` is the only way to map a child cache onto a parent root.

Here `titleSizing` and `subtitleSizing` are `SizeCacheBinding<PairView>` bindings backed by a single `SizeCache<UILabel>`. Each binding takes the `PairView` root and follows its key path to read dependencies and measure the corresponding label. Because both labels share one cache, any unselected label settings that affect size must match across both.

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

If the title and subtitle have different selected values, they produce separate entries in `titleSizes`; if their selected values and proposals match, the second lookup hits the entry from the first. You can mix same-root children and bindings in the same `children:` list.

`bound(to:)` returns a main-actor `SizeCacheBinding<Parent>`, which you can chain with further `bound(to:)` calls for deeper hierarchies. A binding shares the original cache's entries, capacity, and recency order, and adds no storage, key identity, or snapshot depth. Inspect `count` or clear entries on the original `SizeCache`. When assigning a binding to a local variable, include the root type in the key path (such as `\PairView.title`) so Swift can infer `Parent`.

Bindings require nonoptional key paths. Arbitrary mapping closures and conditional child declarations are not supported; express conditions and stable projections in the parent's recipe and selected key paths.

## Declare the children you measure

`SizeCache` cannot see which caches a recipe calls at runtime. List every child cache that can affect the parent's size in `children:`, and capture those same caches or bindings in the recipe. Every declared child contributes its selected values to the parent's snapshot on each lookup, even when a branch in the recipe skips measuring it.

A parent that measured through an undeclared cache would keep returning its own cached entries when only that child's inputs changed. Debug builds catch this: calling `size(of:toFit:)` while another `SizeCache` recipe is running fails an assertion unless the nearest running parent declared that cache in `children:`, either directly or through a child that declares it. A lookup through a binding rooted at the parent must also match a declared path—declaring a title binding and measuring a subtitle binding of the same cache fails—whereas a direct cache call has no comparable path and is checked by cache identity only. Release builds omit this check, and lookups on `MainActorResultCache`, `LayoutCache`, and `ResultCache` are never checked.

If a parent's recipe measures a fixed captured root that no key path from the parent root can reach, pass `allowsUndeclaredMeasurements: true` to that parent's initializer and include the relevant inputs in the parent's own selection. The native UIKit leaf initializer needs no opt-out because the view's `sizeThatFits(_:)` is opaque to the cache. See [declare children](../Documentation/DerivedKeysUI.docc/CacheContract.md#declare-children) for the complete rule.

## Nest a composed layout

A composed `SizeCache` can itself be a child of a higher-level `SizeCache`. Suppose an application's `DocumentCardView` places a `headerLabel: UILabel` above a `contentView: DocumentContentView` with a finite, nonnegative `spacing: CGFloat` gap:

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

Construct and retain the header, document, and card caches once on the main actor. Here `documentCaches` is a `DocumentSizeCaches` bundle and `card` is the view to measure:

```swift
let headerSizes = makeTitleSizes()
let cardSizes = makeCardSizes(headerSizes: headerSizes, contentSizes: documentCaches.contentSizes)
let cardSize = cardSizes.size(
    of: card, toFit: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
)
```

This forms three levels: card, document, and leaf controls. A hit on `cardSizes` skips the entire calculation. Changing only `card.spacing` misses on the card while hitting the cached header and document sizes. Editing the document text misses on the document and the card while reusing the header size. Like the document layout, the card requires a finite proposed width and returns natural height.

The [compiler fixture](../Fixtures/iOS/READMEExamples.swift) defines the minimal `DocumentCardView` root and these calls as test scaffolding rather than a package-owned view.

## Keep proposals with their calculations

A parent keys its outer proposal alongside the values selected from itself and its children. Transformed child proposals do not enter the parent key; instead, each child keys the proposal it receives when the parent recipe calls it. Select padding, axis, visibility, and any other properties that affect how the parent transforms proposals or combines child sizes, and keep the proposal math inside the recipe.

In the document example, the recipe measures children at `max(0, outerWidth - 2 * padding)` and unconstrained height. Changing `spacing` changes only the parent key. Changing `padding` changes both the parent key and the inner width passed to the children. Changing the outer proposed height produces a new parent key even though this layout returns natural height, while the children still receive the same unconstrained height proposal and hit their caches.

See [fitting proposals](../Documentation/DerivedKeysUI.docc/CacheContract.md#fitting-proposals) for valid proposal values and how infinity and signed zero are handled.

## Keep ownership explicit

In the document example, the screen owns a `DocumentSizeCaches` bundle and injects it into reusable views. The bundle exposes the leaf `UITextView` and `UIButton` caches as public properties and creates local bindings for the parent cache; the parent recipe captures only those bindings, not the bundle or any view. Storing a cache on an individual view or in an intentionally shared static property works just as well—the library installs no global storage.

Each cache manages its own capacity and LRU order, so size each capacity for the distinct states you expect that cache to revisit. Parent and child caches evict and clear entries independently; see [capacity, eviction, and clearing](../Documentation/DerivedKeysUI.docc/CacheContract.md#capacity-eviction-and-clearing) and [what a cache retains](../Documentation/DerivedKeysUI.docc/CacheContract.md#what-a-cache-retains).

The document example updates its controls before measurement: text and line limits at initialization and on model updates, and category-only fonts at initialization and on trait updates. Its control getters never mutate the controls. Updating content, calling `setNeedsLayout()`, asking for a fitted size, and assigning the outer frame remain separate application steps owned by the view and its controller.

## Select values the cache can trust

A key path to a `Hashable` class still yields a mutable reference. Project mutable objects into immutable value snapshots—for example, expose a computed `measurementContent` property returning immutable text and style data, and select `\.measurementContent`. See [select stable values](../Documentation/DerivedKeysUI.docc/CacheContract.md#select-stable-values).

### Select authoritative model text

When your model already owns the displayed text, select that model property directly rather than reading text back from UIKit. Here `ArticleView.model` holds an `Article` value whose `text` is a `String`, and updating the model updates `textView.text` before the next measurement:

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

Retain the cache in your chosen owner and call `textSizes.size(of: view, toFit: proposal)`. The [complete iOS 16 compiler fixture](../Fixtures/iOS/ModelTextExample.swift) shows the model, view, and an edit followed by another lookup. It keeps wrapping, text-container insets, line-fragment padding, layout direction, and editing and scrolling settings fixed; if any of those can change, select them as dependencies alongside `\.textView.font`.

Equal Swift strings can have different backing storage and hashing costs. In the [UIKit string measurements](../Benchmarks/String-Results.md), selecting native model text was substantially faster on repeated lookups than reading identical text back from `UITextView`. Note that a model's `String` property is not guaranteed to be contiguous UTF-8 if it was assigned from UIKit, and DerivedKeys does not normalize strings automatically.

When you select a model property, the model and the rendered view must agree during measurement. If editing happens directly in the `UITextView`, update the model before lookup or select `\.textView.text` instead; otherwise a stale model value can reuse an outdated size. Full text works directly as a dependency without content IDs, revisions, or custom wrappers.

### Consider a compact projection after measuring

If profiling shows that hashing full content still dominates lookup time, you can select a content identity together with a revision that increments on every size-relevant edit. Select those existing properties by key path—no wrapper is needed—and continue to select independent typography and layout inputs. Correctness then depends on that revision: missing an edit returns a stale size, and reusing an identity and revision pair for different size-relevant content while entries remain cached can return the wrong measurement. Measure the full request and hit rate before taking on this extra contract; selecting full content remains the default. See the [performance guide](../Benchmarks/README.md#choosing-dependencies-for-an-application) for the measured comparison.

## Inspect snapshots

`snapshot(of:)` returns the captured `DependencySnapshot` for a root so you can inspect or compare selected values in tests and debugging. Because it excludes the fitting proposal, it is not a complete cache key on its own.

## Integrate with UIKit layout

A native-fitting `SizeCache<View>` calls the root view's `sizeThatFits(_:)` on a miss. Do not call that cache from inside that same view's `sizeThatFits(_:)` override, or a miss will [reenter the cache](../Documentation/DerivedKeysUI.docc/CacheContract.md#reentrancy) and fail a precondition. To cache a custom view's `sizeThatFits(_:)`, use the closure initializer with a recipe that measures child caches or calls a separate uncached layout routine.

## Choose a lower-level result API

Use `MainActorResultCache` or `ResultCache` when you want key-path selection for results other than `CGSize`, or when one cached result feeds into the next; see the [result-cache guide](Result-Caches.md). Use `LayoutCache` from `DerivedKeysUI` to cache custom layout structs containing overall size and subview frames, with explicit inputs and an automatically keyed fitting proposal; see the [frame-layout guide](UI-Measurement.md). Use the [generic core](Generic-Core.md) for throwing calculations, typed operation keys, or runtime dependency graphs.
