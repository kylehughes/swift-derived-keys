# Choosing complete dependencies

Choose and capture the inputs that determine a `DerivedKeys` calculation so equal keys always imply interchangeable results.

## Start with the calculation

Include every input that the calculation reads and that can vary across calls, and leave out everything else. A document exporter needs ordered content, format, and export options, plus locale only if the exporter actually reads it; selection state, scroll position, and share callbacks are irrelevant when the algorithm ignores them. A UI measurement needs the effective width and height proposal, metric-affecting content and styles, and any sizing environment it reads. Selecting an unused dependency only costs cache hits, whereas omitting a relevant dependency can return a wrong result.

To keep unrelated calculations from colliding when they happen to take the same dependency types, give each calculation a distinct operation type in ``RequestKey``. Use its `version` parameter when you need to separate concurrently active algorithms; an in-memory cache that starts empty on launch does not need a version number just because an app update changed the code.

## Capture once, then calculate

Build the request key and run the miss calculation from the same captured input state. Reading individually synchronized properties one by one does not form a coherent request if another thread or actor can mutate the model between reads. Instead, capture an immutable input snapshot inside its owner's isolation—or keep key evaluation and the miss calculation together in one non-suspending operation—and pass that snapshot to ``KeyProjection`` or ``KeySource/snapshot(for:)`` and into the cache's miss closure.

When you use ``KeySource``, its providers are ordinary closures that run synchronously during ``KeySource/snapshot(for:)``:

- **Purity and shared nodes.** Providers must perform side-effect-free reads without I/O, suspension, mutation, or recursive graph evaluation. Within a single `snapshot(for:)` call, each shared source node runs at most once. Source identity is used only for this per-request memoization: separate source graphs with the same labels, concrete value types, structure, and captured values produce equal snapshots.
- **Retention and stability.** A ``KeySource`` strongly retains its provider closure and anything the closure captures, while evaluated snapshots own the captured values and structure, and caches own the stored keys and results. Prefer passing an explicit input value into `snapshot(for:)` so a long-lived source does not retain a model owner. If a provider captures an owner weakly, represent a nil owner with a distinct state that cannot match any valid dependency value. Because snapshots do not deep-copy reference types, project immutable values rather than storing mutable `Hashable` objects.
- **Isolation and Sendability.** Neither ``KeySource`` nor its provider closures require `Sendable`. Under Swift 6 region isolation, a source built from actor-isolated closures stays confined to that actor. Typed keys (`RequestKey`, `OriginalKey`, `DerivedKey`, `KeyPair`) and ``MemoizationCache`` are `Sendable` when their type parameters are; erased snapshots (`DependencySnapshot`), sources (`KeySource`), projections (`KeyProjection`), and ``ResultCache`` are not `Sendable`. The `DerivedKeys` module itself is nonisolated and has no main-actor requirement.

## Preserve structure and equality

Snapshots preserve the full structure of your dependency schema:

- Original (leaf) and derived (composite) nodes are never equal to each other.
- Labels distinguish roles within a schema, and child order, multiplicity, optional presence, concrete value types, and child boundaries all affect equality.
- An empty derived composition is a valid constant within its label.
- Use ordered arrays when sequence matters, and normalize unordered inputs into a canonical order before capturing them.
- Immutable construction keeps ``KeySource`` graphs acyclic. Any root-to-leaf path supports up to 64 nodes (``KeySource/maximumDepth``); constructing a deeper graph throws ``KeySource/ConstructionError/maximumDepthExceeded``.

Never use a finalized integer hash (`hashValue` or `Hasher.finalize()`) as a cache key. Hash collisions are normal, so lookup must still compare the complete key for equality, and `Hasher` uses a per-process random seed that makes its output unsuitable for persistence or content identifiers. You can replace a large content projection with an ID and revision pair only if every result-relevant edit increments the revision and that pair uniquely identifies immutable content for the cache's lifetime.

## Compose captured values directly

When you already control how dependencies are read and isolated, you can build a ``DependencySnapshot`` directly without ``KeySource``:

- ``DependencySnapshot/init(value:)`` wraps a single `Hashable` value while preserving its concrete type.
- ``DependencySnapshot/init(children:)`` combines an ordered list of child snapshots under the same 64-node depth limit.

Both initializers use empty labels and compare equal to equivalent empty-label ``KeySource`` snapshots. ``ResultCache`` in `DerivedKeys` and the main-actor caches in `DerivedKeysUI` build their keys from these unlabeled snapshots. Note that `SizeCache` in `DerivedKeysUI` evaluates every declared child occurrence (including bindings) independently on each lookup, whereas ``KeySource`` memoizes shared nodes within a single `snapshot(for:)` call.

The user-facing rules for complete selection, value stability, retention, reentrancy, and clearing are shared across all caches and are stated once in the `DerivedKeysUI` cache contract article.

## Choose the cost you need

For fixed dependency schemas, typed structs (`RequestKey`, `KeyPair`, `OriginalKey`, `DerivedKey`) avoid the per-evaluation node dictionary and child arrays allocated by ``KeySource``. When building a composite ``KeySource``, pass the full child array to ``KeySource/init(_:children:)`` in linear time rather than chaining ``KeySource/appending(_:)`` in a loop, which copies the child array on each step for quadratic total work. Remember that sharing a ``KeySource`` node only avoids running its provider closure more than once per snapshot; hashing and equality still traverse every child position in the resulting tree.

``MemoizationCache`` bounds the number of stored entries (`capacity`), not their byte size, so size its capacity with large keys and results in mind. Copying a `MemoizationCache` or `ResultCache` shares storage until copy-on-write mutation splits it. Because a cache hit skips the calculation closure, keep any side effects that must happen on every call outside the calculation.
