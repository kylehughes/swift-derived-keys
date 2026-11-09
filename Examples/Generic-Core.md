# Using the generic key and memoization APIs

Import `DerivedKeys` to build dependency keys and manage synchronous reuse directly. If you only need to bind key paths and a nonthrowing recipe once, start with `ResultCache` in the [result-cache guide](Result-Caches.md). Reach for the lower-level types in this guide when you want explicit value snapshots, typed operation keys, runtime source graphs, or throwing calculations. The [document exporter](Document-Export.md) shows a complete non-UI calculation backed by a retained `MemoizationCache`.

For UI sizing, the [README](../README.md) introduces `SizeCache`, which builds on the same snapshots and bounded LRU storage. Nothing in `DerivedKeys` requires the main actor.

## Selecting dependencies

### Fixed schemas and explicit snapshots

When a calculation has a fixed set of inputs, capture them in a small `Hashable` value struct. `RequestKey<Operation, Dependencies, Context>` pairs that dependency value with a nominal operation type, an optional algorithm version, and an environment context. Declare a distinct uninhabited enum for each unrelated calculation—even if you store erased keys in an `AnyHashable` dictionary—because string labels alone do not separate operations at the type level.

For smaller or ad hoc schemas, `OriginalKey` labels a single captured value, `DerivedKey` labels a parent composition, and `KeyPair` combines two heterogeneous keys without type erasure; domain structs remain easier to read once a schema grows. `KeyProjection` wraps a synchronous function from an input root to a `RequestKey`:

```swift
import DerivedKeys

enum ExportOperation {}

struct Document {
    var text: String
    var uppercase: Bool
    var isSelected: Bool
}

struct ExportInput: Hashable {
    let text: String
    let uppercase: Bool
}

let projection = KeyProjection(operation: ExportOperation.self) { (document: Document) in
    ExportInput(text: document.text, uppercase: document.uppercase)
}
var document = Document(text: "Hello", uppercase: true, isSelected: false)
let first = projection.key(for: document, context: "plain-text")
document.isSelected = true
let selected = projection.key(for: document, context: "plain-text")
assert(first == selected)
document.uppercase = false
let lowercase = projection.key(for: document, context: "plain-text")
assert(first != lowercase)
```

Here `projection` selects only `text` and `uppercase` from `Document`. Toggling `isSelected` leaves the key unchanged; toggling `uppercase` produces a distinct key. Run your calculation from the `ExportInput` stored on `key.dependencies`, or capture a single input snapshot and pass it to both the projection and the calculation.

Every value stored in a key must keep stable equality and hashing for the key's lifetime. Copying a mutable class reference does not freeze its contents, so project class state into immutable values before building the key; see [select stable values](../Documentation/DerivedKeysUI.docc/CacheContract.md#select-stable-values) for content IDs and revisions.

### Runtime composition and live reads

When dependency structure is assembled at runtime, `KeySource<Input>` describes an immutable directed acyclic graph of dependency reads. Calling `snapshot(for:)` evaluates the graph's provider closures and returns a `DependencySnapshot` holding the captured values and tree structure. Use that snapshot inside a key (`KeySource` itself is not a dictionary key):

```swift
import DerivedKeys

enum RuntimeExportOperation {}

struct RuntimeExportInput {
    let text: String
    let uppercase: Bool
}

let text = KeySource<RuntimeExportInput>("text") { $0.text }
let options = KeySource<RuntimeExportInput>("uppercase") { $0.uppercase }
let source = try KeySource("export", children: [text, options])
let input = RuntimeExportInput(text: "Hello", uppercase: true)
let key = RequestKey(
    operation: RuntimeExportOperation.self,
    dependencies: source.snapshot(for: input),
    context: "plain-text"
)
assert(key.dependencies == source.snapshot(for: input))
```

Providers are ordinary closures, and neither the `Input` nor the returned `Hashable` value needs to be `Sendable`. `KeySource` and `KeyProjection` are not `Sendable` either: Swift 6 region isolation keeps a source built from actor-isolated closures inside that actor's isolation domain, so a source that reads a `@MainActor` object stays on the main actor without extra wrappers or protocols. Always evaluate live state inside the domain that owns its mutations.

In the example below, the provider reads a mutable, non-`Sendable` store and returns its current `String` value. `captureLiveText()` owns both the store and the source for one synchronous scope; earlier snapshots keep their captured strings after the store changes:

```swift
import DerivedKeys

final class DocumentStore {
    var text: String

    init(text: String) {
        self.text = text
    }
}

func captureLiveText() {
    let store = DocumentStore(text: "Hello")
    let source = KeySource<Void>("text", provider: { store.text })
    let first = source.snapshot(for: ())
    store.text = "Goodbye"
    let edited = source.snapshot(for: ())
    assert(first != edited)
    store.text = "Hello"
    assert(first == source.snapshot(for: ()))
}

captureLiveText()
```

During a single `snapshot(for:)` call, each distinct `KeySource` runs its provider once, even when multiple parent sources share it as a child. Deduplicating a shared source within one call does not synchronize separate properties across mutations: capture related state in one synchronous pass and run your calculation before anything mutates. No change notification or `update()` call is needed, and when values change from A to B and back to A, `snapshot(for:)` produces a snapshot equal to the original.

Providers must be synchronous, side-effect-free reads—no I/O, mutation, suspension, or recursive source evaluation. Because a `KeySource` retains its provider closure, avoid strong reference cycles between a source and its owner; evaluated snapshots, keys, and cache entries never retain providers. If a provider captures its owner weakly, return an explicit sentinel when the owner is `nil` rather than fabricating a normal dependency value.

Composed snapshots preserve node labels, leaf (`OriginalKey`) versus derived (`DerivedKey`) kinds, concrete value types, child order, duplicate child occurrences (multiplicity), `Optional` presence, and nesting boundaries. Empty derived compositions are valid. Because arrays and child lists preserve order, use a `Set`, a `Dictionary` (whose `Hashable` conformance is order-independent), or canonical sorting when input order does not affect your calculation—never turn incidental dictionary iteration order into an ordered dependency list.

Sources are immutable: `appending(_:)` returns a new derived `KeySource`, and rebinding a local child variable does not modify existing compositions. When combining many children, pass the array to `init(_:children:)` rather than calling `appending(_:)` in a loop, which copies the child array on each step. Immutable edges prevent cycles, and graph depth is capped at 64 nodes along any path (construction throws if a composition exceeds 64).

## Cache behavior and ownership

`MemoizationCache<Key, Value>` is a bounded LRU cache that takes an explicit nonnegative `capacity` (`0` disables storage while still running the calculation). Hits and newly inserted misses become most recently used, and overflow evicts the least recently used entry. A hit returns the stored value and skips the calculation. If a throwing calculation throws, the error propagates without inserting an entry or evicting existing ones; if an optional calculation returns `nil`, that `nil` is cached and returned as a hit. Use `removeValue(for:)`, `removeAll()`, and `count` to inspect and manage entries.

`MemoizationCache` is a value type with exclusive (`mutating`) access. Copies evolve independently, incurring standard-library copy-on-write costs when mutated. Reentering the same cache during its calculation is unsupported, though composing separate caches is fine. Calculations with side effects that must run on every call do not belong in a cache. The [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md) states the shared rules for value stability, retention, and clearing.

Typed keys (`RequestKey`, `OriginalKey`, `DerivedKey`, and `KeyPair`) and `MemoizationCache` conform to `Sendable` when their stored types do. `KeySource`, `KeyProjection`, `DependencySnapshot`, and `ResultCache` are not `Sendable`, and the inputs and `Hashable` values they read need not be `Sendable` either.

### UIKit cache ownership

For UIKit layout, `DerivedKeysUI` provides `LayoutCache`, a main-actor reference type that shares entries and recency order when you share the reference. It automatically includes the effective fitting proposal in its key and passes the captured inputs into the calculation closure. Cached results can be `CGSize` or a custom layout struct; see the [UIKit guide](UI-Measurement.md) for a complete example.

## Account for cache costs

Dictionary lookup and LRU bookkeeping run in expected amortized O(1) time, excluding key hashing, key equality, and copy-on-write buffer copies. Hashing and comparing keys grows with captured value size and with repeated child occurrences in a snapshot. Likewise, `capacity` bounds entry count rather than byte size, so both retained keys and retained results contribute to memory usage. When profiling justifies it, project large content into a compact immutable value where you control mutations. Swift `Hasher` output is randomly seeded per process—never persist it or replace a full key with its integer hash.

See the [DocC dependency guide](../Documentation/DerivedKeys.docc/DependencyDesign.md) for choosing dependencies, and the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md) for the rules every cache shares.
