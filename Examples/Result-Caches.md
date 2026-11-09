# Cache a result, then use it as input

`ResultCache` and `MainActorResultCache` memoize a synchronous, nonthrowing recipe: they reuse its result when the values selected from the root input match a retained entry. Configure the key paths and recipe once, then look up results across requests—whether the output is a line count, an array of search tokens, or any other value.

Neither type requires its root input or result to be `Hashable` or `Sendable`; only the selected dependency values must conform to `Hashable`. For the rules on complete, stable selections, see the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md).

## Choose `ResultCache` or `MainActorResultCache`

Both accept ordinary key paths and closures, including ones that read main-actor state or call UIKit.

- **`ResultCache`** (from `DerivedKeys`) is a value type. Copying it gives independent entries, and lookups require exclusive mutable access. Because it is not `Sendable`, Swift 6 region isolation confines an instance built from main-actor key paths or closures to the main actor: a main-actor view model can store it directly as a property, and the compiler rejects sending it to another task. Choose it for a single owner, for non-UI code, or when you want value semantics.
- **`MainActorResultCache`** (from `DerivedKeysUI`) is a main-actor reference type. Sharing the reference shares entries and recency order, and reentering it fails a descriptive precondition. Choose it when multiple owners should share one cache or when you want that reentry check.

If you have used React's [`useMemo`](https://react.dev/reference/react/useMemo), the dependency-list model will look familiar, with two differences: `useMemo` compares dependencies against the previous render using `Object.is`, whereas these caches compare value snapshots of the selected `Hashable` properties and retain multiple entries up to `capacity`. Requests for A, then B, then A reuse A's result if its entry is still retained. You choose the cache's owner and call it explicitly; it does not observe changes or schedule rendering.

## Cache one computation

This cache selects the complete string with `\.self` and returns its whitespace-separated tokens:

```swift
import DerivedKeys

var tokens = ResultCache<String, [String]>(
    dependingOn: \.self,
    capacity: 128
) { text in
    text.split(whereSeparator: \.isWhitespace).map(String.init)
}

let words = tokens.value(for: "Cached search tokens")
assert(words == ["Cached", "search", "tokens"])
```

Retain the cache across requests. For a model type, select the properties the recipe actually reads rather than `\.self`. Nested key paths and mixed value types work together, and the model itself need not be `Hashable`. An empty selection gives every input the same key.

Neither cache observes input changes or schedules work.

## Use a line count to cache a view measurement

For collection or table rows with uniform plain-text styling, you can split sizing into two cached stages. First, cache the rendered line count by text, available width, and font. Then use that line count and the remaining layout inputs to cache the row view's `sizeThatFits(_:)` result. Different strings that wrap to the same number of lines share one measured size whenever those other inputs match.

The [complete application example](../Sources/DerivedKeysUIExample/ResultBasedRowMeasurements.swift) pairs `ResultBasedRowMeasurements` with `PlainTextRowView`, a row that fills the proposed width and renders text in a private TextKit 1 `UITextView`. It uses a uniform font, natural line heights, word wrapping, fixed paragraph settings, and no attachments. Both stages select the font; the second also selects horizontal and vertical padding. These are application types you can copy or adapt for your own cells.

Inside the main-actor bundle, named tuples carry the inputs for each stage without custom request or key types:

```swift
private let lineCounts: MainActorResultCache<(text: String, width: CGFloat, font: UIFont), Int>
private let rowSizes: SizeCache<(view: PlainTextRowView, lineCount: Int)>
```

The initializer binds both recipes. `lineCounter` counts actual TextKit line fragments using the same font and wrapping settings as the row:

```swift
lineCounts = MainActorResultCache(
    dependingOn: \.text,
    \.width,
    \.font,
    capacity: lineCountCapacity
) { input in
    lineCounter.count(text: input.text, width: input.width, font: input.font)
}
rowSizes = SizeCache(
    dependingOn: \.lineCount,
    \.view.font,
    \.view.horizontalPadding,
    \.view.verticalPadding,
    capacity: rowSizeCapacity
) { input, proposal in
    input.view.sizeThatFits(proposal)
}
```

The bundle's lookup resolves the two stages in sequence. `textWidth(for:)` subtracts horizontal padding on both sides and validates a finite, positive available text width:

```swift
let count = lineCount(for: row.text, width: row.textWidth(for: proposal.width), font: row.font)
return rowSizes.size(of: (view: row, lineCount: count), toFit: proposal)
```

Only the selected tuple fields enter each key. When `row.text` changes, the first stage looks up a new key; if the resulting line count is unchanged, the second stage hits its cached entry without measuring the row view. Because width affects both wrapping and the row's final `CGSize`, width enters both stages: `MainActorResultCache` does not key or validate dimensions automatically, so the example validates and selects `\.width` for the line counter, while `SizeCache` keys both fitting dimensions automatically.

Here two rows with different text produce separate line-count entries but share one row-size entry:

```swift
let measurements = ResultBasedRowMeasurements()
let firstRow = PlainTextRowView(text: "First")
let secondRow = PlainTextRowView(text: "Second")
let proposal = CGSize(width: 300, height: .greatestFiniteMagnitude)

let firstSize = measurements.size(of: firstRow, toFit: proposal)
let secondSize = measurements.size(of: secondRow, toFit: proposal)
```

Both strings fit on a single line with the default font at width 300. The first lookup measures `firstRow`; the second hits `rowSizes` and reuses that result. Returning to a retained `(text, width, font)` combination hits both stages. Empty text counts as the text view's single empty line, and a trailing newline adds another line.

### Choose an owner and a layout policy

A screen can share one bundle across reusable rows. Each row stores its authoritative Swift text and updates its private text view when text or font changes. The line-count recipe captures only the private TextKit counter, and the sizing recipe measures the row passed for the current request; neither recipe captures the screen or bundle, and cache entries do not implicitly retain rows. The screen still requests a new size and assigns the row's frame when inputs change.

Because this example selects `font` in both stages, a newly resolved Dynamic Type font selects new keys automatically. Padding changes select a new row-size key, and horizontal padding also changes the wrapping width.

If your cells share a single fixed font between Dynamic Type changes, you can omit `font` from both selections and clear the caches when the font changes. Update the views' fonts and clear every affected cache before the next lookup: both the line-count and row-size caches, plus any dependent parent layout cache, since clearing a child does not clear its parents. With the example as written, replacing the bundle resets both stages.

Reusing sizes by line count only works when the row's layout guarantees that equal line counts produce equal sizes:

- **Width:** The row fills the proposed width. Equal line counts do not determine natural text width, so a view that shrinks to fit its text horizontally needs more than a line count in its key.
- **Height:** In the UIKit test samples, this uniform text configuration produced identical fitted heights for equal line counts across empty text, trailing newlines, emoji, and several scripts. A font's [`lineHeight`](https://developer.apple.com/documentation/uikit/uifont/lineheight) does not guarantee that for every layout: mixed fonts, paragraph spacing, and attachments can give equal line counts different heights. For those layouts, pass richer measured geometry between stages or keep the text in the size key. Verify against the content and rendering settings your application supports before dropping text from the size key.

Profile the full two-stage lookup against direct view fitting before adopting it for speed. Counting lines for nonempty text still runs TextKit layout on a first-stage miss, and cache hits still capture, hash, and compare dependencies. This example shows how to stage caches; it does not establish a speedup.

### How this differs from size-cache children

In a staged lookup, your code queries the first cache and passes its output into the second. Because the second cache keys the computed line count and remaining layout inputs, different strings that wrap to the same number of lines can share one measured size.

With `SizeCache` `children:`, by contrast, each child contributes its own selected dependency values directly to the parent's key. That lets a parent hit skip its recipe and all child lookups. Use [size-cache composition](Size-Caches.md) when a parent should short-circuit unchanged subtrees, and use explicit result stages when different inputs collapse to the same intermediate value. Neither API automatically discovers caches called inside a recipe.

## Ownership, removal, and correctness

`ResultCache` is a value type: copies start with the same entries and then mutate independently, without deep-copying objects held in entries or captures. `MainActorResultCache` is a reference type, so sharing it shares entries and recency order; reentering it during dependency capture or calculation—including reading `count` or removing entries—fails a precondition, while its immutable `capacity` stays readable. Calling a distinct cache from inside a recipe is supported.

Retention, stable projections, and clearing follow the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md). On both result caches, `removeValue(for:)` reads the input's current dependency values to form the key to remove, and `removeAll()` clears only that cache while keeping its recipe. Clearing either stage in a pipeline does not clear the other: if an undeclared external change affects both calculations, clear both caches or rebuild their owner. Clearing entries does not replace values captured directly by a recipe closure, so rebuild any cache whose recipe captured an outdated font or fixed setting.

Configured recipes are synchronous and nonthrowing. For throwing calculations or explicit request keys, use the [generic core APIs](Generic-Core.md), including `MemoizationCache`. For `CGSize` measurements with automatically keyed fitting proposals, use `SizeCache`.
