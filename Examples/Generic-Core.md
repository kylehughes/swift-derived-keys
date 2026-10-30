# Using the generic key and memoization APIs

Import `DerivedKeys` for non-UI computations, explicit snapshots, runtime source graphs, or typed operation keys. The [document exporter](Document-Export.md) shows a complete non-UI computation with a retained cache. The [sizing convenience API](../README.md) uses the same snapshots and bounded storage while owning its main-actor measurement recipe.

## Selecting dependencies

### Fixed schemas and explicit snapshots

Use a small `Hashable` value struct for the inputs of one operation. `RequestKey<Operation, Dependencies, Context>` adds a nominal operation type, algorithm version, and environment. Declare a separate operation enum for unrelated calculations, including when storing requests in an `AnyHashable` dictionary. A free-form label does not separate operations.

`OriginalKey` labels one captured value. `DerivedKey` labels a composition, and `KeyPair` holds two heterogeneous children without type erasure. Domain structs make larger fixed schemas readable. `KeyProjection` stores a reusable synchronous function from explicit input to dependencies:

```swift
import DerivedKeys

enum ExportOperation {}
struct ExportInput: Hashable {
    let text: String
    let uppercase: Bool
}

let projection = KeyProjection(operation: ExportOperation.self) { (input: ExportInput) in
    DerivedKey("export", children: input)
}
let input = ExportInput(text: "Hello", uppercase: true)
let key = projection.key(for: input, context: "plain-text")
```

Keep every value's equality and hashing stable for the lifetime of a key. `Hashable` does not ensure immutability: copying a mutable class reference is not a snapshot. Project its content into immutable values instead. A content ID alone cannot describe edits under that ID. A revision is sufficient only if it covers every relevant mutation, is paired with a unique content identity, and the pair is not reused for different content while entries may remain.

### Runtime composition and live reads

`KeySource<Input>` is an immutable graph recipe. Providers run when `snapshot(for:)` is called. Sources are deliberately not dictionary keys; `DependencySnapshot` contains the evaluated values and structure used in keys.

```swift
let text = KeySource<ExportInput>("text") { $0.text }
let options = KeySource<ExportInput>("uppercase") { $0.uppercase }
let source = try KeySource("export", children: [text, options])
let input = ExportInput(text: "Hello", uppercase: true)
let key = RequestKey(
    operation: ExportOperation.self,
    dependencies: source.snapshot(for: input),
    context: "plain-text"
)
```

The closure convenience requires `@Sendable`, so an actor-isolated closure cannot be silently stored as a nonisolated callback. Inputs and returned `Hashable` values need not be `Sendable`. For live non-Sendable state, conform a reader to `KeyValueProvider` and pass it as `provider:`. Its `nonisolated value(for:)` method makes the execution contract explicit without making the reader transferable. `KeyProjection` also accepts this reader form. Keep that state within its mutation owner.

Providers must be synchronous, side-effect-free reads: no I/O, mutation, suspension, or recursive evaluation. Actor-isolated properties belong in an explicit snapshot captured by the actor before calling the source. Sources retain their providers, so avoid owner/source capture cycles; evaluated keys and cache entries do not retain those providers. A weak-owner adapter should represent a missing owner explicitly, never fabricate a valid dependency value.

Each distinct source is read once per evaluation, even when shared by several parents. That memoization does not synchronize different properties or sources. Capture related state together, then calculate from the same snapshot without an intervening mutation. No change notification or `update()` call is needed. When values return A → B → A, the original key is restored.

Composition preserves labels, original versus derived nodes, concrete value types, order, multiplicity, optional presence, and nested boundaries. Empty derived compositions are valid. `appending` returns a new derived source; rebinding a child variable does not change an existing composition. Build large collections with `init(_:children:)`: repeated appends copy the child array. Graph depth is limited to 64 nodes per path; construction throws beyond that bound. Immutable edges prevent graph cycles.

Arrays preserve order. For unordered inputs, use a `Set`, a dictionary with its own order-independent `Hashable` semantics, or canonicalize according to the calculation. Do not turn incidental dictionary iteration order into an ordered dependency list.

## Cache behavior and ownership

`MemoizationCache<Key, Value>` requires an explicit nonnegative capacity. Zero disables storage. Hits and successful insertions become most recently used; overflow evicts the least recently used entry. A hit skips the calculation. A thrown calculation propagates its error without insertion or eviction; a cached optional `nil` is a hit. Use `removeValue(for:)`, `removeAll()`, and `count` to manage storage.

The cache is a value type with exclusive mutation. Copies evolve independently, with standard-library copy-on-write costs on later mutation. Reentering the same cache during its calculation is unsupported; separate caches can be composed. Results, like keys, must not change meaning through mutable external aliases. Computations whose side effects must run on every call do not belong in this cache.

Typed keys and caches are `Sendable` only when their stored values are. Dynamic sources, projections, and erased snapshots are not `Sendable`. Their input and captured value types need no transfer conformance; non-Sendable live readers use `KeyValueProvider`, while the closure conveniences require `@Sendable`. The generic library has no main-actor requirement.

### UIKit cache ownership

`DerivedKeysUIKit.LayoutCache` is a main-actor reference type: sharing it shares its entries and recency order. It automatically includes the effective fitting proposal and supplies captured inputs to the calculation. Results can be `CGSize` or your own layout struct. It does not retain calculation closures; callers control the values retained by keys and results. Changing a model, scheduling layout, and assigning the resulting size remain application responsibilities.

## Account for cache costs

Dictionary indexing and LRU bookkeeping are expected amortized O(1), excluding key hashing/equality and copy-on-write. Key work can grow with content size and repeated child occurrences. The capacity bounds entry count, not bytes: retained keys and results both matter. When profiling warrants it, prepare reusable immutable projections where you control content changes. Swift `Hasher` output is process-local; never persist it or replace a semantic key with its integer hash.

See the [DocC dependency guide](../Documentation/DerivedKeys.docc/DependencyDesign.md) for the full ownership and equality contract.
