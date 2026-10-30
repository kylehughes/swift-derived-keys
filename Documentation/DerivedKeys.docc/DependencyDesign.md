# Choosing complete dependencies

Capture the inputs that determine one calculation, and preserve their meaning for as long as the key is retained.

## Start with the calculation

For an exporter, project ordered content, format, and options. Include locale only if the exporter reads it. Selection, scrolling, and share callbacks are irrelevant when the algorithm does not consume them. For UI measurement, effective width and height, metric-affecting content and style, and any environment used by sizing belong in the request. Including extra dependencies costs cache hits; omitting a relevant one can return a wrong result.

A distinct operation enum supplies a nominal namespace through ``RequestKey``. Use its version to separate concurrently valid algorithms when needed. A cache discarded on launch does not need a version solely because an app update changes code.

## Capture once, then calculate

Pass an immutable input to ``KeyProjection`` or ``KeySource/snapshot(for:)`` and use that input in the cache's miss closure. Reading individually synchronized properties at different times does not establish a coherent request. Capture related state together within its mutation owner, or keep evaluation and calculation in one non-suspending operation in that owner's isolation.

Live providers execute synchronously during source evaluation. Closure providers are `@Sendable`; a non-Sendable reader can conform to ``KeyValueProvider`` instead, whose synchronous read is explicitly nonisolated. Actor-owned state belongs in an explicit input snapshot captured by the actor. Providers must perform side-effect-free reads without I/O, suspension, mutation, or recursive evaluation. Shared sources are captured once per request; memoization identity never contributes to semantic equality. Different source instances with equal schemas and values produce equal snapshots.

The source retains its provider, including any objects the provider captures strongly. The snapshot owns values and structure, and the cache owns keys and results. Prefer explicit inputs to avoid retaining a model through a source. A weak capture must distinguish owner disappearance from a valid dependency. None of these abstractions deep-copy arbitrary references: capture immutable content instead of a mutable `Hashable` object.

Typed snapshots and caches transfer only when their components are `Sendable`. Erased snapshots and source recipes deliberately do not promise transfer safety. The generic module is nonisolated; a UI adapter captures and measures within the main actor.

## Preserve structure and equality

Original and derived nodes are different forms. Labels distinguish roles; order, multiplicity, optional presence, concrete value types, and child boundaries remain significant. Empty compositions are constants in their labeled schema. Use arrays for ordered data and an order-independent representation for unordered data. Immutable construction keeps graph edges acyclic. Runtime graphs support up to 64 nodes per root-to-leaf path; deeper construction throws.

Never use a finalized integer hash as a semantic key. Collisions are legal, and dictionary equality must still compare the complete key. `Hasher` output is process-local, unsuitable for serialization or a stable content identifier. An ID plus revision can replace a large content projection only when every relevant mutation changes the revision and the pair uniquely identifies immutable content within the cache's scope.

## Compose captured values directly

``DependencySnapshot/init(value:)`` retains a full hashable value and its concrete type. ``DependencySnapshot/init(children:)`` composes already captured snapshots in order, with the same 64-node depth bound. These unlabeled forms use empty labels and compare equal to equivalent empty-label source snapshots. They are useful when the caller already owns selection and isolation; the core adds no UI or global-actor dependency.

The sizing facade in `DerivedKeysUI` captures main-actor key-path values into this representation. Its traversal evaluates each declared occurrence independently, including mapped bindings; that differs from `KeySource`'s request-local shared-node memoization. Both preserve complete values and structure.

## Choose the cost you need

Typed structs avoid the erased graph's per-evaluation node dictionary and arrays. A bulk source initializer constructs an ordered child collection in linear time; repeated immutable appends can take quadratic total work. Provider work is separate from hashing and equality, which inspect content and repeated child occurrences. A shared graph node saves provider reads, not necessarily all later key hashing.

``MemoizationCache`` uses bounded LRU storage. Its capacity bounds entries rather than bytes, so account for retained key content and results. Standard-library copy-on-write can copy storage after a cache value is copied. A cache hit skips the calculation entirely, so side effects required on every request must occur outside it.
