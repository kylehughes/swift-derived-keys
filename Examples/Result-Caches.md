# Cache a result, then use it as input

`ResultCache` and `MainActorResultCache` memoize a calculation: they reuse its result when the selected dependency values match a retained entry. Bind the key paths and calculation once, then look up results across requests. A result can be a line count, an array of search tokens, or any other value.

Use `ResultCache` from `DerivedKeys` for nonisolated calculations. Use `MainActorResultCache` from `DerivedKeysUI` when the recipe reads main-actor state or calls UIKit. Neither type requires its input or result to be `Hashable`; only selected dependency values must be hashable.

If you know React's [`useMemo`](https://react.dev/reference/react/useMemo), the dependency-list idea is familiar. `useMemo` compares dependencies with their previous-render values using `Object.is`. These caches compare snapshots of the selected `Hashable` values and retain multiple results up to their capacity. Requests A, B, then A can reuse the first result if its entry is still retained. You choose the cache's owner and call it explicitly; it does not observe changes or schedule rendering.

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

Retain the cache across requests. For an application model, select its relevant properties instead of `\.self`. Nested paths and mixed value types work, and the model itself need not be hashable or sendable. An empty dependency selection gives every input the same key, so use it only for a calculation whose result does not vary with the input.

`ResultCache` requires sendable key paths and a `@Sendable` calculation. These requirements keep actor-isolated reads out of the nonisolated cache API; ordinary nonisolated key-path literals infer the required conformance. When your key paths or calculation need main-actor access, use `MainActorResultCache`. Neither cache observes input changes or schedules work.

## Use a line count to cache a view measurement

For collection or table rows with consistent plain-text styling, you can cache measurement in two stages. First, cache the rendered line count by text, available width, and font. Then use that count and the remaining layout inputs to cache the view's actual `sizeThatFits(_:)` result. Different strings that occupy the same number of lines can share a measured size when those other inputs match.

The [complete application example](../Sources/DerivedKeysUIExample/ResultBasedRowMeasurements.swift) pairs `ResultBasedRowMeasurements` with `PlainTextRowView`, a row that fills the proposed width and renders text in a private TextKit 1 `UITextView`. It uses a uniform font, natural line heights, word wrapping, fixed paragraph settings, and no attachments. Both stages select the font; the second also selects horizontal and vertical padding. These are application types you can copy or adapt for your own cells.

Inside the main-actor bundle, named tuples carry the inputs without custom request or key types:

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

The bundle's lookup resolves the stages explicitly. `textWidth(for:)` subtracts per-side horizontal padding and validates a finite, positive available text width:

```swift
let count = lineCount(for: row.text, width: row.textWidth(for: proposal.width), font: row.font)
return rowSizes.size(of: (view: row, lineCount: count), toFit: proposal)
```

Only the selected fields enter each key. Text changes select a new first-stage key; if the resulting count is unchanged, the second stage can hit without measuring the row. Width changes affect wrapping and the row's full `CGSize`, so width belongs in both stages. `MainActorResultCache` does not automatically key or validate dimensions; the example does that for its line counter. `SizeCache` automatically includes both fitting dimensions and validates the proposal.

For example, these two rows have separate text entries but share one row-size entry:

```swift
let measurements = ResultBasedRowMeasurements()
let firstRow = PlainTextRowView(text: "First")
let secondRow = PlainTextRowView(text: "Second")
let proposal = CGSize(width: 300, height: .greatestFiniteMagnitude)

let firstSize = measurements.size(of: firstRow, toFit: proposal)
let secondSize = measurements.size(of: secondRow, toFit: proposal)
```

Both strings occupy one line with the example's default font at this width. The first lookup measures `firstRow`; the second reuses that result. Returning to a retained text, width, and font combination can reuse both stages. Empty text counts as the text view's one empty line, and a trailing newline adds another line.

### Choose an owner and a layout policy

A screen can share one bundle across reusable rows. Each row stores its authoritative Swift text and updates its private text view when text or font changes. The line-count recipe captures the private TextKit counter; the sizing recipe uses the row supplied for the current request. Neither recipe captures the screen or bundle, and entries do not implicitly retain rows. The screen still requests a new size and assigns the row's frame when inputs change.

This example selects font in both stages, so a newly resolved Dynamic Type font selects new keys. Padding changes select a new row-size key; horizontal padding also changes the wrapping width.

If your cells share one fixed font between Dynamic Type changes, you can instead omit font from your own bundle's keys and reset the caches when it changes. Update the views' fonts and clear every affected cache before the next lookup: both the line-count and row-size caches, plus any dependent parent layout cache. Clearing a child does not clear its parents. With the example as written, replace the bundle to reset both stages.

Reusing sizes by line count depends on the row's layout:

- **Width:** The row fills the proposed width. Equal line counts do not determine text's natural width, so a view that fits its width to its text needs more than a line count in its key.
- **Height:** In the UIKit test samples, this uniform text configuration produced equal fitted heights for equal line counts, including empty text, trailing newlines, emoji, and several scripts. A font's [`lineHeight`](https://developer.apple.com/documentation/uikit/uifont/lineheight) does not account for every layout: mixed fonts, paragraph spacing, and attachments can give equal counts different heights. For those layouts, pass richer measured geometry between stages or keep the original size-affecting dependencies in the size key. Check the content and rendering configuration your application supports before dropping text from that key.

Measure the complete two-stage lookup against direct view fitting before choosing it for performance. Counting nonempty text's lines runs TextKit layout on a first-stage miss, and cache hits still capture, hash, and compare dependencies. This example has not demonstrated a speedup.

### How this differs from size-cache children

Here the caller resolves the first cache and passes its output to the second. The second cache keys the computed line count and the remaining layout inputs, so different strings that wrap to the same number of lines can share one measured size.

`SizeCache` children contribute their original dependency values to a parent's key. That lets a parent hit skip its calculation and all child lookups. Use [size-cache composition](Size-Caches.md) when that behavior fits the layout; use explicit result stages when different inputs can produce the same intermediate result. Neither API discovers caches called by a recipe.

## Ownership, removal, and correctness

`ResultCache` is a value type. Copies start with the same entries and then mutate independently; copying does not deep-copy objects in entries or recipe captures. The facade is not `Sendable` and provides no shared synchronization. Its mutating operations require exclusive access, and same-cache reentry is unsupported.

`MainActorResultCache` is a reference type. Sharing it shares entries and LRU recency. Reentering it during dependency capture or calculation, including reading `count` or removing entries, fails a precondition. Calls to distinct caches are supported. Its immutable `capacity` remains readable during an operation.

Both caches retain their configured recipe. Entries retain selected snapshots and results without implicitly retaining input roots; selected reference values, results, and explicit captures can retain objects. Choose stable immutable projections when a hashable object has mutable aliases. Inputs must remain consistent from dependency selection through calculation, and the selected values must cover everything that can change the result.

Each cache has its own capacity, including zero to disable storage. `removeValue(for:)` selects the input's current dependency values; `removeAll()` clears only that cache and keeps its recipe. Clearing either stage does not clear the other. If an undeclared external change affects both calculations, clear both caches or rebuild their owner. Clearing entries does not replace captured configuration; rebuild any recipe that captured an old font or other fixed setting.

Configured recipes are synchronous and nonthrowing. For throwing calculations or explicit request keys, use the [generic core APIs](Generic-Core.md), including `MemoizationCache`. `SizeCache` remains the convenience for `CGSize` results with automatically keyed fitting proposals.
