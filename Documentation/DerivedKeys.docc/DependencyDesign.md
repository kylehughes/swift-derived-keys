# Choosing complete dependencies

Use this guide to choose the inputs for a generic `DerivedKeys` request. Capture the inputs that determine one calculation, and preserve their meaning for as long as the key is retained. Equal keys must imply interchangeable results.

## Start with the calculation

For an exporter, project ordered content, format, and options. Include locale only if the exporter reads it. Selection, scrolling, and share callbacks are irrelevant when the algorithm does not consume them. For UI measurement, effective width and height, metric-affecting content and style, and any environment used by sizing belong in the request. Including extra dependencies costs cache hits; omitting a relevant one can return a wrong result.

A distinct operation enum supplies a nominal namespace through ``RequestKey``. Use its version to separate concurrently valid algorithms when needed. A cache discarded on launch does not need a version solely because an app update changes code.

## Capture once, then calculate

Capture an immutable input, pass it to ``KeyProjection`` or ``KeySource/snapshot(for:)``, and calculate from the same input in the cache's miss closure. Reading individually synchronized properties at different times does not establish a coherent request. Capture related state together within its mutation owner, or keep evaluation and calculation in one non-suspending operation in that owner's isolation.

Live ``KeySource`` providers run synchronously during ``KeySource/snapshot(for:)``. Closure providers require `@Sendable`; a non-`Sendable` reader can conform to ``KeyValueProvider``, whose synchronous read is explicitly `nonisolated`. For actor-owned state, capture an explicit value snapshot inside the actor and pass it as input.

Providers must perform side-effect-free reads without I/O, suspension, mutation, or recursive graph evaluation. Each shared source is evaluated once within a single snapshot request. Source identity is used only for this memoization: separate source graphs with equal labels, concrete value types, structure, and captured values produce equal snapshots.

A source retains its provider and any objects the provider captures strongly. Evaluated snapshots own captured values and structure, and caches own keys and results. Prefer explicit inputs to avoid retaining a model through a long-lived source. If a provider captures an owner weakly, represent the owner's disappearance distinctly from any valid dependency value. Snapshots do not deep-copy arbitrary references, so project immutable content instead of storing mutable `Hashable` objects.

Typed snapshots and caches transfer only when their components are `Sendable`. Erased snapshots and source recipes deliberately do not promise transfer safety. The generic module is nonisolated; a UI adapter captures and measures within the main actor.

## Preserve structure and equality

Original and derived nodes are different forms. Labels distinguish roles; order, multiplicity, optional presence, concrete value types, and child boundaries remain significant. Empty compositions are constants in their labeled schema. Use arrays for ordered data and an order-independent representation for unordered data. Immutable construction keeps graph edges acyclic. Runtime graphs support up to 64 nodes per root-to-leaf path; deeper construction throws.

Never use a finalized integer hash as a semantic key. Collisions are legal, and dictionary equality must still compare the complete key. `Hasher` output is process-local, unsuitable for serialization or a stable content identifier. An ID plus revision can replace a large content projection only when every relevant mutation changes the revision and the pair uniquely identifies immutable content within the cache's scope.

## Compose captured values directly

``DependencySnapshot/init(value:)`` retains a full hashable value and its concrete type. ``DependencySnapshot/init(children:)`` composes already captured snapshots in order, with the same 64-node depth bound. These unlabeled forms use empty labels and compare equal to equivalent empty-label source snapshots. Use them when the caller already controls dependency selection and isolation; the core adds no UI or global-actor dependency.

The sizing facade in `DerivedKeysUI` captures main-actor key-path values into this representation. Its traversal evaluates each declared occurrence independently, including mapped bindings; that differs from `KeySource`'s request-local shared-node memoization. Both preserve complete values and structure.

## Choose the cost you need

Typed structs avoid the erased graph's per-evaluation node dictionary and arrays. A bulk source initializer constructs an ordered child collection in linear time; repeated immutable appends can take quadratic total work. Provider work is separate from hashing and equality, which inspect content and repeated child occurrences. A shared graph node saves provider reads, not necessarily all later key hashing.

``MemoizationCache`` uses bounded LRU storage. Its capacity bounds entries rather than bytes, so account for retained key content and results. Standard-library copy-on-write can copy storage after a cache value is copied. A cache hit skips the calculation entirely, so side effects required on every request must occur outside it.
