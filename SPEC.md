**Technical specification: dependency-composed keys in Swift**

**1. Purpose and scope**

Implement a reusable Swift library for deriving hashable keys from the subset of state that affects a particular computation.

A primary use case is caching UI measurements: two model configurations can reuse a component’s measured size when their layout-relevant state and measurement environment are equivalent, even if other model properties differ.

The core must remain domain-independent. It must support computations such as document transformation, parsing, formatting, or other deterministic derived values without importing UI frameworks or assuming the main actor.

Separate three responsibilities:

- Selecting and composing dependencies.
- Evaluating those dependencies into an immutable key.
- Using the key to reuse a computed result.

A cache is one consumer of the key abstraction. UI measurement is one application of that cache.

Use Swift 6 language mode and strict concurrency checking. Build with the latest stable Swift toolchain, recording the exact compiler, package tools version, supported platforms, and default actor isolation. The generic target must not inherit UI-specific isolation.

In this specification, **must** identifies a correctness or delivery requirement; **should** identifies a recommendation that requires a documented reason to depart from; **may** identifies an optional extension. This is an implementation contract, not a claim that an implementation has already been tested.

**2. Fundamental correctness contract**

For a computation:

```text
result = compute(model, context)
key    = project(operation, model, context)
```

the application must uphold:

```text
key(a) == key(b)  implies  compute(a) and compute(b) are interchangeable
```

“Interchangeable” includes everything the caller observes in the returned result. Cached computations must not depend on side effects that need to occur on every call.

The reverse implication is unnecessary. Two different keys may produce equal results. Conservatively including an extra dependency reduces cache hits but remains correct; omitting a dependency that can change the result can return a wrong result.

A key expresses equivalence for one computation, not necessarily model equality, entity identity, or visual equality.

Do not change a model’s general-purpose `Equatable` or `Hashable` conformance to implement this narrower equivalence. Define a separate projection or key type. One model may expose several projections for different computations.

Examples:

| Change | Text measurement | Exported document |
| --- | --- | --- |
| Text content changes | Relevant | Relevant |
| Available width changes | Relevant | Usually irrelevant |
| Share-action callback changes | Irrelevant | Irrelevant |
| Export format changes | Irrelevant | Relevant |

These classifications depend on the actual calculation. The library cannot infer complete dependencies from a model’s fields.

**3. Sources, composition, and evaluated keys**

Provide three conceptual building blocks. Public names may differ, but their semantics must remain explicit.

**Original source.** A labeled leaf that supplies a `Hashable` dependency value. Support direct immutable values and a provider that obtains the current value. A provider is evaluated when the key is requested, not only when the source is constructed.

**Derived source.** A labeled, ordered composition of original or derived sources. Compositions may contain heterogeneous value types and may nest. Appending a dependency creates a new composition and leaves the old composition unchanged.

**Evaluated key.** An immutable, value-semantic snapshot of the dependency values and their structure. This is the object used as a dictionary key. A live source whose output changes over time must never itself be stored as a dictionary key.

Dependency inputs must have stable equality and hashing for the lifetime of an evaluated key. `Hashable` alone does not guarantee this. For mutable reference-backed state, callers must supply an immutable projection or an explicit snapshot operation; retaining the reference is insufficient. The library does not automatically deep-copy arbitrary values.

The conceptual snapshot representation is:

```text
Original(label, value-type, captured-value)
Derived(label, ordered-child-snapshots)
Request(operation-domain, algorithm-version, dependencies, context)
```

The implementation may encode these distinctions through concrete generic types rather than storing textual tags or runtime type metadata.

Required composition semantics:

- Labels distinguish dependency roles within a declared schema.
- Original and derived forms are distinct.
- Dependency order, multiplicity, optional presence, and collection boundaries are preserved.
- Empty derived compositions are valid constants within their namespace.
- Nested structure is preserved; do not silently flatten it.
- Replacing a variable used to build a composition does not retroactively modify that composition.
- Shared live sources may supply new values on later evaluations; previously evaluated keys remain unchanged.
- Independent source instances with equal schemas and equal captured values produce equal keys. Source object identity is not part of result equivalence.

An ordered collection must use order-sensitive equality. Unordered input must use an order-independent representation or explicit canonicalization appropriate to the computation. Do not rely on incidental dictionary iteration order.

Prefer typed structs and generic composition on common paths. Type erasure may support heterogeneous runtime collections, but must preserve node kind, namespace, concrete value-type distinctions, structural equality, and ownership/isolation constraints. Erasure must not reduce each dependency to an integer.

**4. Hashing and equality**

Use Swift `Hashable` semantics: equal keys must hash equally; equal hashes do not establish equal keys. Hashing selects candidates; equality determines whether reuse is valid. [Swift Hashable documentation](https://developer.apple.com/documentation/swift/hashable).

The cache must retain enough information to compare complete semantic keys. Store entries by a `Hashable` key, rather than by its `hashValue` or a finalized `Int` alone.

A hash collision must never return another key’s result. This applies at every composition level: retaining only child hashes discards information before the parent key is formed.

A precomputed digest is permitted as an optimization if it is derived from an immutable snapshot and equality still checks the semantic key when necessary. Equal keys must use the same hashing scheme and seed policy.

Swift `Hasher` output is process-local and may change between executions or standard-library versions. Do not persist it, transmit it as a stable identifier, or promise deterministic numeric values. Stable serialization and cryptographic fingerprints are separate features. [Swift Hasher documentation](https://developer.apple.com/documentation/swift/hasher).

An operation’s namespace must distinguish computations that happen to receive the same dependency values. Prefer separate nominal key types or a typed operation token. Shared erased storage must preserve that distinction. A free-form diagnostic label alone is insufficient to prevent unrelated operations from sharing entries accidentally.

Algorithm versions distinguish concurrently valid implementations when necessary. A process-local cache discarded on launch does not need versioning solely for app updates.

**5. Evaluation, mutation, and consistency**

The required baseline is **pull on evaluation**:

1. Capture the inputs for one calculation request.
2. Evaluate the relevant dependency projection.
3. Form one immutable request key.
4. Look up that key.
5. On a miss, calculate from the same captured inputs and store the result under that key.

The original concept reevaluates provider closures when a hash is read. Preserve that ability. Do not introduce a requirement to send change notifications before a later lookup can observe changed state.

Provide an explicit-input path, such as a projection from an immutable input snapshot, as the preferred way to maintain consistency and avoid retaining a model owner. A live provider adapter may capture current state within its owner’s isolation and then use the same path.

Providers must be synchronous, side-effect-free reads for the duration of evaluation. They must not mutate dependencies, recursively evaluate the same source graph, perform I/O, or suspend. Capture time, randomness, external configuration, or resource versions explicitly if they affect the computation.

A request must represent one coherent input state. Merely reading several individually synchronized properties is insufficient if their values can change between reads. Capture related state together or evaluate and calculate in one non-suspending operation within its mutation owner’s isolation.

If a shared source appears multiple times, every occurrence in one evaluation must observe the same captured value. This can follow from an immutable input snapshot; a graph evaluator may instead use request-local memoization. Evaluation identity used for memoization must not become part of the semantic key.

Support acyclic composition. Immutable construction from existing children is the preferred baseline. If mutable graph edges or recursive custom sources are exposed, detect cycles and fail with a documented diagnostic rather than hanging or overflowing the stack.

Do not expose an `update()` method that silently does nothing. If a later optimization introduces pushed invalidation, specify it separately, including mutation coverage, dependency propagation, ownership, revision semantics, and overflow handling. It must not change the meaning of equal keys.

When all captured dependency values return to their previous values, the evaluated key must equal the previous key. Content revisions may conservatively prevent reuse after content returns to an earlier value; document this behavior.

**6. Generic cache contract**

Supply a small generic reference cache to demonstrate consumption of the keys. Its key and result types must be independent of UI frameworks.

A suitable API shape is:

```swift
// Contract sketch; exact spelling is an implementation decision.
struct MemoizationCache<Key: Hashable, Value> {
    init(capacity: Int)

    mutating func value(
        for key: Key,
        compute: () throws -> Value
    ) rethrows -> Value

    mutating func removeValue(for key: Key)
    mutating func removeAll()
}
```

Requirements:

- A hit returns the cached value and does not invoke `compute`.
- A miss invokes `compute` once for that synchronous call, returns its result, and inserts it on success.
- A thrown error creates no entry and propagates to the caller.
- A cached `Optional.none` must remain distinguishable from a missing entry.
- Equal keys must refer to interchangeable computations even if callers provide different closure instances. Closure identity is not a key.
- Cache keys and results must not change through externally mutable aliases in a way that changes their promised meaning. Prefer value types or documented immutable references.
- Require an explicit nonnegative capacity. Zero disables storage while still allowing computation.
- Use a documented bounded eviction policy. LRU is the reference policy: hits and successful insertions mark entries most recently used, and excess entries evict the least recently used.
- Provide per-key removal, full clearing, and a readable entry count.
- Eviction affects performance, not result correctness.

The cache owns evaluated keys and results. It must not retain providers, calculation closures, views, or entire source graphs after a request merely to support a cached entry.

A synchronous value-type cache with exclusive mutation is sufficient for the baseline. Reentering the same cache during `compute` is unsupported and must be documented. Separate caches may be composed.

A shared concurrent or async cache is optional. If supplied, define duplicate-miss behavior, cancellation, failures, reentrancy, and clearing while work is in flight. Capture the request key before suspension, calculate from that request’s snapshot, and prevent cleared work from repopulating the cache under an obsolete generation. Do not add these complexities to the synchronous baseline without a use case.

**7. Swift concurrency and ownership**

Keep pure key construction and immutable snapshots nonisolated. Add `Sendable` conformances only when stored components satisfy the corresponding transfer requirements.

The baseline must not require every `Hashable` value or every provider to be `Sendable`. An actor-confined UI source is a legitimate client. Conversely, generic cache use must not require the main actor.

UI adapters must access UI state and perform UI measurements on the main actor. They should capture plain dependency values there; those values can cross isolation boundaries only when their types support it.

Provider APIs must accurately express their execution isolation. Do not store an actor-isolated closure as an ordinary nonisolated closure or use unchecked `Sendable` conformances to suppress a design mismatch.

Choose one owner for mutable cache storage: exclusive value ownership, an actor, or a documented synchronization wrapper. A lock around the cache does not make the source model safe to read concurrently.

Avoid ownership cycles between an owner, its stored sources, and their closures. Prefer passing explicit input snapshots. If a weak owner capture is used, represent owner disappearance explicitly; do not fabricate a default dependency that might hit an unrelated valid entry.

**8. UI measurement example**

Demonstrate a text component containing content and an optional expansion button.

A representative dependency graph is:

```text
text measurement
  ├─ rendered text or a trustworthy content revision
  ├─ metric-affecting text attributes
  ├─ expansion / truncation policy
  ├─ effective fitting constraints
  └─ typography environment

button measurement
  ├─ resolved title / image metrics
  ├─ button style and typography
  └─ effective fitting constraints

component measurement
  ├─ text measurement dependencies
  ├─ button visibility
  ├─ button measurement dependencies, when visible
  ├─ spacing and padding
  └─ outer fitting constraints
```

Parent keys compose child dependency keys, plus the inputs used only by the parent. The values of child measurements may also be cached independently.

Include every input actually read by the sizing algorithm: potentially width, bounded height, fitting priorities, font metrics, Dynamic Type, locale, layout direction, line limits, paragraph spacing, attachments, padding, and display scale when rounding depends on it. Do not add every trait indiscriminately; document the subset used.

The sizing adapter must include the effective fitting proposal automatically. Passing a width to `compute` while omitting it from the key violates this contract.

Represent unconstrained dimensions explicitly. Reject NaN and invalid negative finite dimensions at the adapter boundary. Translate framework-specific unbounded sentinels into a documented representation. If dimensions are quantized, use the same normalized values for both the key and the actual measurement; rounding the key alone can produce wrong hits.

Hash rendered content or a projection of its metric-affecting properties. A stable document ID alone is insufficient if its text or styling can change. An ID plus revision is valid only if every relevant change updates the revision and the pair uniquely identifies immutable content within the cache’s scope.

Action callbacks, analytics identifiers, unrelated URLs, and paint-only colors should be omitted when the sizing algorithm does not consume them. Changing button visibility must affect the component key even when it does not affect the text key.

View reuse must work without view identity in the key: two views with equivalent inputs may share a result, while a reused view with different inputs must request a different key.

Changing a dependency, requesting another size, scheduling layout, and publishing that size to a container are separate actions. The hashing library must not claim to schedule or repair UI layout automatically.

**9. Non-UI example**

Demonstrate a document exporter with the same key primitives and cache:

```text
export key
  ├─ ordered projected document content
  ├─ export format
  ├─ relevant export options
  ├─ locale, if used
  └─ exporter algorithm version, if needed
```

Exclude selection state, scrolling position, view dimensions, and share callbacks.

Changing an export option must recompute the output. Changing an unrelated UI property must reuse it. This example must compile in the generic package without UIKit, AppKit, SwiftUI, or CoreGraphics.

**10. Performance requirements**

Measure key work separately from the expensive computation being cached.

- Avoid allocations on repeated lookups where concrete value keys suffice.
- Construct dependency lists in one pass. Repeated immutable appends must not impose quadratic construction work on the recommended bulk-building path.
- Do not reread or rehash large immutable content unnecessarily. Precompute reusable projections at content creation or controlled mutation boundaries where profiling supports it.
- A revision may replace a large projection only with an explicit identity, mutation-coverage, and non-reuse contract. Never use an arbitrary short hash as a collision-free revision.
- Request-local memoization may eliminate repeated visits to shared sources.
- Use iterative evaluation or a documented supported depth when graphs can be deeply nested.
- Bound cache entries and account for retained key data as well as results. Avoid retaining large parent objects through otherwise small projections.
- Do not claim constant-time lookup overall: projection, hashing, and equality have costs proportional to the inspected data. Dictionary indexing and LRU bookkeeping should be expected amortized constant time apart from those costs.
- Start with standard-library facilities. Add macros, custom storage, or specialized graph machinery only when a measured need justifies them.

Benchmark release builds for direct computation, cold misses, warm hits, changing relevant inputs, changing irrelevant inputs, large payloads, shared dependencies, and eviction. Report compiler, hardware, workload, key cost, computation count, allocations where measurable, and retained memory. Do not set an unsupported universal speedup target.

**11. Acceptance criteria and deliverables**

Implement deterministic tests covering:

| Scenario | Required outcome |
| --- | --- |
| Same semantic inputs evaluated repeatedly | Equal keys; calculator skipped on retained hits |
| Irrelevant model field changes | Equal key and reused result |
| Relevant projected field changes | Unequal semantic key; appropriate recomputation |
| Captured dependency values change A → B → A | Original A key restored; reuse if retained |
| Only fitting width changes | Distinct UI request keys and correct measurements |
| Content changes under an unchanged entity ID | New key through content or revision |
| Equal inputs for different operations | No cross-operation reuse |
| Unequal values deliberately returning the same hash | Distinct cached results at leaf, nested, and root levels |
| Dependency order, count, optional presence, or nesting changes | Equality follows the specified structure |
| New dependency appended to a composition | Original composition remains unchanged |
| Shared source used more than once | One coherent value throughout a request |
| Previously captured key followed by model mutation | Old key remains unchanged |
| Computation throws | No insertion; later lookup can retry |
| Result is `Optional.none` | Stored and retrieved as a hit |
| Capacity zero, overflow, hit, removal, and clear | Documented storage and LRU behavior |
| Owner and cache are released | No unintended retention from providers or entries |
| Non-UI example | Uses the same generic core without UI dependencies |

Do not assert that unequal keys always have different integer hashes. Test semantic equality and collision handling instead.

For concurrency-related APIs, add positive compilation fixtures for supported usage and negative fixtures for prohibited isolation crossings under the same compiler settings. Run deterministic race/reentrancy tests only for concurrency features actually shipped.

Deliver:

- A Swift package containing the generic key/source abstractions.
- The bounded generic reference cache.
- A UI measurement example or separate optional adapter.
- A runnable non-UI example.
- API documentation covering equality, dependency completeness, evaluation timing, isolation, lifetimes, and complexity.
- Automated tests and reproducible release benchmarks.
- Exact build/test commands, results, and any unsupported configurations.

The implementation is complete when these contracts are implemented and the applicable checks pass. The implementing agent must report gaps explicitly rather than treating the specification itself as validation.
