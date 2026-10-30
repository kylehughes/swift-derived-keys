# Composing size caches

Import `DerivedKeysUI` to bind key-path dependencies and a measurement closure in a retained `SizeCache`. The [README](../README.md) starts with a single measurement and composes a text/button layout. The [complete application fixture](../Sources/DerivedKeysUIExample/DocumentContentView.swift) defines `DocumentContentView`, the screen-owned `DocumentSizeCaches` bundle, and a controller that assigns frames. These are example application types; the library does not require them.

## Map a child root

A child can measure a nested root. `at(_:)` maps its dependency description; call the original child with that mapped root inside the calculation:

```swift
import DerivedKeysUI
import UIKit

@MainActor
func makeTitleSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 128) { label, proposal in
        label.sizeThatFits(proposal)
    }
}

@MainActor
final class PairView: UIView {
    let title = UILabel()
    let subtitle = UILabel()
}

@MainActor
func makePairSizes(titles: SizeCache<UILabel>) -> SizeCache<PairView> {
    SizeCache<PairView>(
        children: titles.at(\.title), titles.at(\.subtitle),
        capacity: 128
    ) { view, proposal in
        let title = titles.size(of: view.title, toFit: proposal)
        let subtitle = titles.size(of: view.subtitle, toFit: proposal)
        return CGSize(width: max(title.width, subtitle.width), height: title.height + subtitle.height)
    }
}
```

The label recipe assumes every other measurement setting is fixed. A title and subtitle with different selected values produce separate child requests through the same cache. Each mapping captures its own root binding; the subtitle cannot accidentally reuse the title's snapshot during traversal. Equal child inputs and proposals may intentionally reuse a result. Same-root children can appear alongside mapped children in one initializer.

Mappings do not unwrap optional roots. Arbitrary mapping closures and conditional child declarations are not supported. Map a nonoptional key path or keep the condition and any required stable projection in the parent recipe. Declared children are always captured, even if the calculation takes a branch that does not measure them. The facade does not discover caches called by a closure: list the children that determine the parent result and capture those same handles in its calculation.

## Keep proposals with their calculations

The parent keys its own proposal and recursively captured dependency values. Children do not contribute a proposal until their calculations are actually requested. Padding, orientation, visibility, and other values used in transformation or combination belong in the parent selection. There is no need to declare the transformation twice.

The document example measures inner content at `max(0, outerWidth - 2 * padding)` and unconstrained height. Changing spacing changes only the parent key. Changing padding also changes the child's actual width. Changing the outer height changes the parent request even though this example chooses natural height; its unchanged child proposals can still hit.

Both proposal axes must be finite and nonnegative. `CGFloat.greatestFiniteMagnitude` denotes an unconstrained axis; infinity is rejected. Signed zero becomes positive zero in both key and callback proposal. Dimensions are not quantized. The recipe controls result sizing, including any rounding or clamping.

## Keep ownership explicit

The document screen owns a `DocumentSizeCaches` bundle and injects it into reusable views. Its initializer creates local text and button handles, then creates the parent using those same handles. Parent closures capture the children, not the bundle or a view. Each cache has its own capacity and LRU order. A view-owned cache and an intentionally static cache are equally valid; no global storage is installed by the package.

Descriptions retain dependency readers only. A descriptor from `child.at(\.title)` does not retain the child's measurement closure or entries. The parent closure must retain any child handle it will call. Cached entries contain captured values and `CGSize` results; the root supplied to `size(of:toFit:)` is not implicitly retained. Explicit user captures or reference-valued dependencies can still retain a root or owner.

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

If full-content hashing still dominates, an optional compact projection is the content's identity together with a reliable revision that changes on every size-relevant edit. Select those existing properties by key path; no wrapper is needed. Independent typography and layout inputs still need dependencies. A revision that misses an edit makes reuse incorrect. Do not reuse an identity/revision pair for different size-relevant content while affected entries may remain. See the [performance guide](../Benchmarks/README.md#choosing-dependencies-for-an-application) before choosing a projection.

## Inspect snapshots and composition limits

Selection and calculation are synchronous on the main actor. Keep selected values and any other result-relevant state consistent throughout the request. Dependency getters should read values without mutation, I/O, or recursive evaluation. A hit still reads all declared dependencies and hashes/compares their full snapshots, but does not invoke measurements or consult child result storage. `snapshot(of:)` exposes the dependency snapshot for inspection; it excludes proposal and recipe identity and is not a standalone complete result key.

Public construction cannot create a cycle in the immutable graph. Its limit is 64 snapshot nodes per path, counting value leaves and composition boundaries. Mapping adds no boundary. An empty cache has depth one; a cache selecting a property has depth two; a parent adds one. Excess depth fails a descriptive precondition. Same-cache measurement reentry, including result inspection/removal through an alias, also fails a precondition; nesting different caches is supported.

## Integrate with UIKit layout

Changing content, scheduling a UIKit layout pass, asking for another size, and assigning the outer frame remain separate application actions. The document example synchronizes its text and category-only font settings before a direct leaf measurement; it schedules layout when content or category changes. The controller remains responsible for refitting and assigning the container frame.

## Choose a lower-level result API

Use `DerivedKeysUIKit.LayoutCache` when you want to cache an application-defined result containing complete child frames as well as overall size. Its [frame-layout guide](UI-Measurement.md) shows that explicit-input API. Use the [generic core](Generic-Core.md) for other computations, throwing calculations, typed operation keys, or nonisolated ownership.
