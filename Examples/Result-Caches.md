# Cache a result, then use it as input

`ResultCache` and `MainActorResultCache` bind selected key paths and a calculation once. They can return a line count, an array of search tokens, or any other value. The calculation runs only when the selected values have no retained result.

Use `ResultCache` from `DerivedKeys` for nonisolated calculations. Use `MainActorResultCache` from `DerivedKeysUI` when the recipe reads main-actor state or calls UIKit. Neither type requires its input or result to be `Hashable`; only selected dependency values must be hashable.

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

`ResultCache` accepts sendable key paths and a `@Sendable` calculation, allowing synchronous use within a chosen owner without granting actor access. Ordinary nonisolated key-path literals infer the required conformance. Use `MainActorResultCache` for main-actor properties and closures. Neither cache observes input changes or schedules work.

## Pass a line count into a height cache

A row layout can reuse two different results: text wrapping for a particular string and width, and the row height for a particular line count. Different strings can wrap to the same count and share the second result.

The [complete application example](../Sources/DerivedKeysUIExample/ResultBasedRowMeasurements.swift) defines `ResultBasedRowMeasurements`. This is example code to copy or adapt, not an installed library type. It uses TextKit to count actual line fragments. Its plain-text policy fixes the font, line height, wrapping, and padding for the bundle's lifetime; rendering must use that same policy. Empty text has zero lines. A paragraph separator at the end of nonempty text contributes a final empty line.

Inside that main-actor bundle, the cache declarations are:

```swift
private let lineCounts: MainActorResultCache<(text: String, width: CGFloat), Int>
private var rowHeights: ResultCache<Int, CGFloat>
```

The initializer configures both recipes. `lineCounter` is the example's private TextKit helper; `lineHeight` and `verticalPadding` are fixed values supplied at construction:

```swift
lineCounts = MainActorResultCache(
    dependingOn: \.text,
    \.width,
    capacity: lineCountCapacity
) { input in
    lineCounter.count(text: input.text, width: input.width)
}
rowHeights = ResultCache(dependingOn: \.self, capacity: rowHeightCapacity) { count in
    CGFloat(count) * lineHeight + verticalPadding
}
```

A request resolves the stages explicitly:

```swift
let count = lineCounts.value(for: (text: text, width: width))
let height = rowHeights.value(for: count)
```

Named tuples carry multiple inputs without a custom request or key type. Only selected fields enter the key: `\.width` is necessary because width affects wrapping. These general-purpose caches do not automatically key, validate, or normalize fitting dimensions. The example validates finite positive width before lookup and expects the available text width after horizontal padding.

With the example's default typography and a width of 300 points, `"First"` and `"Second"` each occupy one line. Their text measurements have separate entries, while the height cache has one entry. Changing width selects another first-stage key; its resulting count determines whether the second stage can reuse a height. Returning to a retained text-and-width combination can reuse both results.

This example's height formula is inexpensive. Calculate it directly when a second cache adds no useful savings. The two caches demonstrate result-based reuse, not a measured speedup. A hit still reads dependencies and hashes and compares snapshots.

### Choose an owner and a layout policy

A screen can retain one `ResultBasedRowMeasurements` bundle and supply heights to reusable rows. Pass authoritative model text directly; there is no need to read it back from a text view. The recipe captures the private TextKit helper, not its screen or bundle.

Recreate the example bundle when its fixed typography changes, including a resolved Dynamic Type change. Another application can represent variable style as selected dependencies. A line count alone cannot determine height when fonts, line spacing, paragraph spacing, attachments, or other geometry vary. Attributed text and variable line heights are outside this example's policy; the general cache APIs impose no text policy.

### How this differs from size-cache children

Here the application resolves the first cache before looking up the second. The second cache keys the resulting count, so different first-stage inputs can share a result.

`SizeCache` children contribute their original dependency values to a parent's key. That lets a parent hit skip its calculation and all child lookups. Use [size-cache composition](Size-Caches.md) when that behavior fits the layout; use explicit result stages when a computed value should become the next input. Neither API discovers caches called by a recipe.

## Ownership, removal, and correctness

`ResultCache` is a value type. Copies start with the same entries and then mutate independently; copying does not deep-copy objects in entries or recipe captures. The facade is not `Sendable` and provides no shared synchronization. Its mutating operations require exclusive access, and same-cache reentry is unsupported.

`MainActorResultCache` is a reference type. Sharing it shares entries and LRU recency. Reentering it during dependency capture or calculation, including reading `count` or removing entries, fails a precondition. Calls to distinct caches are supported. Its immutable `capacity` remains readable during an operation.

Both caches retain their configured recipe. Entries retain selected snapshots and results without implicitly retaining input roots; selected reference values, results, and explicit captures can retain objects. Choose stable immutable projections when a hashable object has mutable aliases. Inputs must remain consistent from dependency selection through calculation, and the selected values must cover everything that can change the result.

Each cache has its own capacity, including zero to disable storage. `removeValue(for:)` selects the input's current dependency values; `removeAll()` clears only that cache and keeps its recipe. Clearing either stage does not clear the other. If an undeclared external change affects both calculations, clear both caches or rebuild their owner.

Configured recipes are synchronous and nonthrowing. For throwing calculations or explicit request keys, use the [generic core APIs](Generic-Core.md), including `MemoizationCache`. `SizeCache` remains the convenience for `CGSize` results with automatically keyed fitting proposals.
