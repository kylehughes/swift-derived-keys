# Technical specification: dependency-composed keys in Swift

See the [README](README.md) for package usage and the [maintenance guide](Documentation/Maintenance.md) for local check commands. This specification defines the normative requirements for the generic `DerivedKeys` core, the `DerivedKeysUI` module, and their validation suites.

[Correctness contract](#2-fundamental-correctness-contract) · [Key-path sizing](#8a-key-path-size-recipes) · [Performance](#10-performance-requirements) · [Acceptance](#11-acceptance-criteria-and-deliverables)

## 1. Purpose and scope

Implement a reusable Swift library that derives hashable keys from the subset of state affecting a specific computation.

A primary use case is caching UI measurements: two model states can reuse a component's measured size whenever their layout-relevant properties and measurement environment match, even if unrelated model properties differ.

The core module (`DerivedKeys`) must remain domain-independent. It must support deterministic derived computations—such as document transformation, parsing, and formatting—without importing UI frameworks or assuming main-actor isolation.

The design must separate three responsibilities:

- Selecting and composing dependencies.
- Evaluating those dependencies into an immutable key.
- Using the key to reuse a computed result in a cache.

A cache is one consumer of the key abstraction, and UI measurement is one application of that cache.

Build in Swift 6 language mode with strict concurrency checking enabled under the latest stable Swift toolchain, recording the exact compiler version, SwiftPM tools version, minimum deployment targets, and default actor isolation. The generic core target must not inherit UI-specific actor isolation.

In this specification, **must** identifies a mandatory correctness or delivery requirement, **should** identifies a strong recommendation that requires a documented reason to depart from, and **may** identifies an optional extension. This document specifies the required contract; conformance is established only by passing the validation suite.

## 2. Fundamental correctness contract

For a computation:

```text
result = compute(model, context)
key    = project(operation, model, context)
```

the application must uphold:

```text
key(a) == key(b)  implies  compute(a) and compute(b) are interchangeable
```

"Interchangeable" covers every aspect of the returned value that the caller observes. Cached computations must not rely on side effects that need to run on every request.

The converse does not need to hold: two unequal keys may legitimately produce equal results. Including an extra dependency conservatively reduces cache hits without breaking correctness, whereas omitting a dependency that can alter the result can return a wrong result.

A key represents equivalence for a single computation, not general model equality, entity identity, or visual identity. Callers must not alter a model's general-purpose `Equatable` or `Hashable` conformance to express calculation-specific equivalence; instead, define a separate projection or key for each calculation. A single model may have different projections for different calculations:

| Change | Text measurement | Exported document |
| --- | --- | --- |
| Text content changes | Relevant | Relevant |
| Available width changes | Relevant | Usually irrelevant |
| Share-action callback changes | Irrelevant | Irrelevant |
| Export format changes | Irrelevant | Relevant |

Whether an input is relevant depends on what the calculation actually reads; the library cannot infer completeness from a model's stored properties.

## 3. Sources, composition, and evaluated keys

Provide three conceptual building blocks (public type names may differ, provided these semantics remain explicit):

- **Original source.** A labeled leaf node that supplies a `Hashable` dependency value, supporting both constant immutable values and a provider closure that reads the current value on evaluation. Providers must run when a key snapshot is requested, not only when the source is constructed.
- **Derived source.** A labeled, ordered composition of original or derived sources. Compositions may combine heterogeneous value types and nest arbitrarily (up to the supported depth limit). Appending a child source must return a new composition and leave the existing composition unchanged.
- **Evaluated key.** An immutable, value-semantic snapshot of the captured dependency values and their structure, suitable for use as a `Dictionary` key. A live source whose output can change over time must never itself conform to `Hashable` or be used directly as a dictionary key.

Every captured dependency value must keep stable equality and hashing for the lifetime of an evaluated key. Conforming to `Hashable` is not sufficient by itself: for mutable reference types, callers must project an immutable value snapshot rather than storing the mutable reference. The library does not deep-copy arbitrary reference graphs automatically.

Conceptually, snapshots have three forms:

```text
Original(label, value-type, captured-value)
Derived(label, ordered-child-snapshots)
Request(operation-domain, algorithm-version, dependencies, context)
```

An implementation may encode these forms in static generic types on typed paths rather than storing string tags or runtime type metadata.

Compositions and snapshots must satisfy these structural rules:

- Labels distinguish dependency roles within a schema.
- Original (leaf) and derived (composite) forms never compare equal to each other.
- Child order, multiplicity, optional presence (`Optional.some` vs `Optional.none`), and collection boundaries are preserved.
- Empty derived compositions are valid constants within their labeled namespace.
- Nested hierarchy is preserved and never silently flattened.
- Rebinding a variable used to construct a composition does not mutate that composition.
- Shared live sources may return different values on subsequent evaluations without altering previously evaluated keys.
- Independent source graphs with identical schemas and equal captured values produce equal snapshots; source instance identity does not affect key equality.

Ordered collections must use order-sensitive equality, while unordered inputs must use an order-independent representation or explicit canonicalization suited to the calculation. Never depend on `Dictionary` or `Set` iteration order.

Prefer static generic structs on fixed-schema paths. Type-erased snapshots may support heterogeneous runtime graphs, provided erasure preserves node kind (leaf vs composite), label namespace, concrete leaf value type, structural equality, and isolation rules. Type erasure must never collapse a dependency leaf into an integer hash alone.

## 4. Hashing and equality

Follow standard Swift `Hashable` semantics ([Swift `Hashable` documentation](https://developer.apple.com/documentation/swift/hashable)): equal keys must produce equal hashes, while equal hashes do not imply equal keys. Hashing selects bucket candidates; full key equality decides whether a cached result may be reused.

Caches must retain complete semantic keys and store entries by a `Hashable` key type rather than by `hashValue` or a finalized `Int` digest alone. A hash collision must never return another key's cached result at any level of composition—retaining only child hashes before forming a parent key is prohibited because it discards value equality. A precomputed hash digest may be cached alongside an immutable snapshot as an optimization only if `==` still compares the full semantic key when hashes match, and equal keys always use the same hashing scheme and seed policy.

Swift `Hasher` output is randomly seeded per process and may vary across launches or standard-library releases ([Swift `Hasher` documentation](https://developer.apple.com/documentation/swift/hasher)). Never persist `Hasher` output, transmit it across processes, or use it as a content identifier.

Operation namespaces must keep unrelated calculations from colliding when they happen to select the same dependency types and values. Use distinct nominal operation types (or typed operation tokens) and preserve that separation across type-erased storage; a free-form string label alone is insufficient to isolate unrelated operations. Use an explicit algorithm `version` when concurrently active algorithms must coexist; an in-memory cache discarded on process launch does not require versioning solely for app binary updates.

## 5. Evaluation, mutation, and consistency

The baseline evaluation model is **pull on evaluation**:

1. Capture the inputs for a single request.
2. Evaluate the dependency projection against those inputs.
3. Form an immutable request key.
4. Look up the key in the cache.
5. On a miss, run the recipe against those same captured inputs and store the result under that key.

Reevaluating a source graph must invoke its providers for the current request, whereas hashing or comparing an already-evaluated snapshot must read only its stored values. Callers must not be required to post invalidation notifications before a subsequent lookup can observe updated state.

Provide an explicit-input path—projecting a key from an immutable input value—as the primary mechanism for keeping key evaluation and miss calculation consistent without retaining a model owner. Live provider closures may read state within their owner's actor isolation and delegate to the same snapshot representation.

During evaluation, providers must be synchronous, side-effect-free reads: they must not mutate dependencies, recursively evaluate the same source graph, perform I/O, or suspend. Any time, randomness, external configuration, or resource version that affects the output must be captured as an explicit input.

A request must observe a single coherent state. Reading individually synchronized properties one by one is insufficient if concurrent mutations can interleave between reads; either capture related state atomically into a value snapshot or run key evaluation and miss calculation together inside one non-suspending turn of the state owner's isolation.

When a shared `KeySource` node appears multiple times in one graph, every occurrence within a single `snapshot(for:)` call must observe the same captured value, either because all reads draw from an immutable input or through request-local node memoization. The node identity used for request-local memoization must not enter the semantic key.

Compositions must be acyclic. Immutable bottom-up construction is the baseline; if mutable edges or recursive sources are ever exposed, cycles must be detected deterministically rather than hanging or overflowing the call stack.

Do not expose no-op invalidation stubs (such as an `update()` method that does nothing). If push-based invalidation is added in the future, specify its mutation coverage, propagation, ownership, revision overflow, and equivalence rules separately.

When all selected dependencies change from `A` to `B` and back to `A`, the evaluated key must again equal the original `A` key (unless the caller explicitly uses a monotonic content revision that conservatively treats the reverted edit as a new revision, which must be documented).

## 6. Generic cache contract

Provide a bounded, generic value-type cache in `DerivedKeys` whose key and value types have no UI framework dependencies:

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

`MemoizationCache` must satisfy these requirements:

- **Hit behavior:** A cache hit returns the stored value without calling `compute`.
- **Miss behavior:** A cache miss calls `compute` once synchronously, returns its result, and stores the entry if `compute` succeeds.
- **Error handling:** If `compute` throws, the cache must not insert or overwrite an entry and must rethrow the error to the caller.
- **Optional values:** When `Value` is an `Optional`, a cached `.none` (`nil`) must be stored and returned as a hit, distinct from a missing key.
- **Closure independence:** Equal keys must represent interchangeable results regardless of closure identity; `compute` is never part of the key.
- **Value stability:** Stored keys and results must not mutate through external reference aliases in ways that alter key equality or result semantics.
- **Capacity and LRU eviction:** Require an explicit nonnegative `capacity` (`capacity < 0` fails a precondition). A capacity of `0` disables storage while still running `compute` on every call. Positive capacities use least-recently-used (LRU) eviction: hits and insertions mark the entry as most recently used, and inserting into a full cache evicts the least recently used entry. Eviction affects only hit rate, never correctness.
- **Inspection and removal:** Expose `count`, `capacity`, `removeValue(for:)`, and `removeAll()`.
- **Entry retention:** The cache retains only evaluated keys and results—never provider closures, per-request `compute` closures, views, or source graphs.
- **Exclusivity and reentrancy:** Exclusive `inout` mutation is sufficient for the synchronous value-type cache. Reentering the same cache instance from inside `compute` is unsupported and must be documented; composing distinct cache instances is supported.

Concurrent or `async` caches are outside the baseline. If introduced later, they must separately specify duplicate-in-flight miss coalescing, task cancellation, error propagation, reentrancy, and generation-safe clearing across suspension points.

## 7. Swift concurrency and ownership

Keep pure key construction and immutable snapshots `nonisolated`, and add conditional `Sendable` conformances only where all stored type parameters are `Sendable`.

The generic core must not require every `Hashable` dependency, input, result, key path, or closure to be `Sendable`, and must not require `@Sendable` closures or a custom provider protocol to express actor isolation. `KeySource`, `KeyProjection`, `DependencySnapshot`, and `ResultCache` are intentionally not `Sendable`: under Swift 6 region isolation, an instance constructed from actor-isolated key paths or closures stays confined to that actor's isolation region. That allows a `@MainActor` type to own a `ResultCache` or `KeySource` directly while making cross-task transfers fail at compile time. Conversely, non-UI callers can use `DerivedKeys` off the main actor.

UI caches in `DerivedKeysUI` must isolate dependency reads and view measurements to `@MainActor`. Never use `@unchecked Sendable` or isolation-erasing casts to silence compiler diagnostics.

Each mutable cache must have a single concurrency owner (exclusive value ownership for `MemoizationCache` and `ResultCache`, or `@MainActor` isolation for `SizeCache`, `MainActorResultCache`, and `LayoutCache`). Synchronizing a cache does not synchronize the underlying model being read.

Avoid reference cycles between an owner, its caches or sources, and their closures by passing explicit roots or inputs into lookups. If a closure captures an owner `weak`, represent a deallocated owner with a dedicated state that cannot collide with any valid dependency value.

## 8. Reusable UIKit support and UI measurement examples

The README's primary example must use `DerivedKeysUI.SizeCache` to cache a single view measurement and to compose text, button, and container sizes. In the `DocumentContentView` example, frame-based layout uses native-fitting leaf caches and bound child handles inside the parent recipe, with the cache bundle publicly retaining the leaf caches and parent cache. View property getters only read controls; initialization and model setters eagerly synchronize content and line limits, and initialization and trait-change callbacks synchronize fonts. Scheduling layout and refitting the outer container remain the application's responsibility.

`LayoutCache`—which takes explicit inputs and stores complete frame layouts—serves as the explicit-input alternative.

### 8a. Key-path size recipes

#### Products

The package must expose exactly two library products:

- `DerivedKeys`: the standard-library-only generic core.
- `DerivedKeysUI`: the UI product containing `SizeCache`, `SizeCacheBinding`, `SizeDependencies`, `MainActorResultCache`, `LayoutCache`, `LayoutInputs`, `LayoutKey`, `FittingProposal`, `FittingDimension`, and `FittingProposalError`.

No other library product provides UI support. Keep the tested text, button, and layout examples in a non-product example target (`DerivedKeysUIExample`).

#### Construction and lookup

`SizeCache<Root>` is a `@MainActor` reference type. It provides two initializers:

- **Closure initializer:** binds a parameter pack of heterogeneous `Hashable` key paths on `Root`, an optional ordered list of child dependency descriptions (`children:`), an explicit local `capacity`, an `allowsUndeclaredMeasurements` flag (defaulting to `false`), and one synchronous measurement recipe closure. Works with any `Root` type, including non-UIKit types.
- **UIKit convenience initializer (`where Root: UIView`):** binds heterogeneous `Hashable` key paths on `Root` and an explicit local `capacity`, with no child list and no recipe closure. On a miss, it calls `root.sizeThatFits(_:)` with the normalized effective proposal. A native-fitting cache must not be called from inside the measured view's own `sizeThatFits(_:)` override, which reenters the same cache and fails a precondition; custom view overrides must use the closure initializer instead.

Lookups use `size(of:toFit:)`. `Root` does not need to conform to `Hashable` or `Sendable`, and zero selected key paths (and zero children on the closure initializer) are valid. Callers do not need string labels, type-erased wrappers, custom input structs, operation enums, macros, or result builders. Neither initializer infers omitted dependencies, enforces recipe purity, or prevents mutation of `Hashable` reference types.

#### Bind child roots

`SizeCache.bound(to:)` maps a child cache onto a parent root via a nonoptional `KeyPath<Parent, Root>`, returning a `final` `@MainActor` `SizeCacheBinding<Parent>` subclass of `SizeDependencies<Parent>`. It is the only supported way to adapt a child cache to a different root type:

- A binding exposes `size(of:toFit:)` and chainable `bound(to:)`, retains the underlying `SizeCache` for measurement, and adds no separate result storage, key namespace, or snapshot depth.
- A binding's API is measurement-only; `count`, `capacity`, `removeSize(of:toFit:)`, and `removeAll()` live on the underlying `SizeCache`.
- Passing a child or binding in `children:` retains only its dependency readers—not the binding, child cache storage, or child recipe. The parent's recipe closure must capture the bound handles or child caches it calls.
- Same-root children can be passed directly in `children:`. Independent bindings, chained bindings, and multiple bindings to the same underlying child cache read their respective key paths independently.
- `SizeDependencies` must be closed to external subclassing and expose only `snapshot(of:)` and `maximumDepth`. Composition is acyclic, with a checked maximum of 64 snapshot nodes along any root-to-leaf path (including value leaves).

#### Declared children

Every child `SizeCache` whose measurement contributes to a parent `SizeCache` recipe must be declared in the parent's `children:` list (directly or through a binding):

- In debug builds, calling `size(of:toFit:)` on a `SizeCache` while another `SizeCache` recipe is running must fail an assertion unless the nearest running parent declared that cache—either directly in its own `children:` or transitively through a declared child.
- If the lookup is made through a `SizeCacheBinding` rooted at the running parent's `Root` type, the binding's key path must also match a declared binding path; if the lookup calls the cache directly or through a binding rooted at a different type, the check verifies cache identity only.
- A parent whose recipe measures a fixed captured root unreachable by any key path from the parent root can opt out by passing `allowsUndeclaredMeasurements: true`.
- The UIKit convenience initializer is exempt from the check because `UIView.sizeThatFits(_:)` is opaque to the cache.
- Release builds must compile out the check and all of its bookkeeping state. `MainActorResultCache`, `ResultCache`, and `LayoutCache` lookups are never checked.

#### Keys and proposals

Each `SizeCache` key stores the full, type-preserving selected values in their ordered recursive child structure alongside both effective proposal dimensions. Because each cache owns private storage, keys do not need to encode recipe or cache identity. Capturing a dependency snapshot never runs a measurement recipe, reads child result storage, or substitutes child sizes into the parent key; every declared child contributes its selected values to the parent key even when a branch skips measuring that child. Parents must select all variable inputs that affect proposal transforms, branching, or child combination; proposal transforms happen inside the parent recipe, and each measured child keys the proposal passed to it.

`SizeCache` validates proposals without throwing:

- Finite nonnegative dimensions are preserved without rounding, and signed zero (`-0.0`) normalizes to `0.0`.
- `CGFloat.greatestFiniteMagnitude` and `+infinity` are both treated as unconstrained axes, and the recipe receives `CGFloat.greatestFiniteMagnitude` for either.
- NaN, `-infinity`, negative dimensions, negative `capacity`, snapshot depth above 64, and same-cache reentry must fail descriptive preconditions. Generic throwing APIs (`FittingProposal(fitting:)`, `FittingDimension(points:)`, `KeySource`) keep their throwing behavior.

#### Storage and ownership

Each `SizeCache` wraps its own bounded LRU storage with independent `count`, `capacity`, `removeSize(of:toFit:)`, `removeAll()`, and capacity-zero behavior:

- A parent hit returns the cached size and skips both the parent recipe and all child lookups; a parent miss runs the recipe and may hit warm child caches.
- Evicting or clearing a child entry does not change the child's dependency snapshot and therefore never invalidates retained parent entries; clearing a parent clears only the parent's entries.
- Never share a single mutating value cache across recursive recipes, and check for same-cache reentry before touching underlying storage.
- Callers must keep size-relevant state consistent across synchronous `@MainActor` dependency reads and recipe execution, and project immutable snapshots for mutable reference properties.
- A cache retains its recipe closure (and any explicit captures), while cache entries never implicitly retain lookup roots. Applications choose whether to own a cache per view, per screen, or statically, and remain responsible for calling `setNeedsLayout()` and assigning frames.

#### Validation

Tests and benchmarks for `SizeCache` must cover:

- Heterogeneous, nested, and empty dependency selections; changes to selected and unselected properties; and hash-collision keys.
- Both proposal axes and normalization, including `+infinity`, `-0.0`, and parent-transformed child proposals.
- Parent-only and child-only mutations, parent hits skipping child recency updates, three-level composition, all `bound(to:)` forms, and lookup-root deallocation.
- Bounded LRU eviction, `capacity: 0`, and independent parent/child clearing.
- Debug declared-children assertions: declared pass, undeclared assertion failure, `allowsUndeclaredMeasurements: true` pass, and nested parents.
- Compilation of real UIKit key paths against the iOS 16 Simulator target under Swift 6.4, isolated child-process checks for precondition traps, and benchmark measurements of snapshot capture, warm parent hits, parent misses with warm children, cold composed misses, and direct UIKit fitting.

### 8b. Explicit layout caching

`DerivedKeysUI` must also provide `FittingProposal`, `FittingDimension`, `FittingProposalError`, `LayoutInputs`, `LayoutKey`, and `LayoutCache`—a bounded `@MainActor` reference cache for caller-defined layout result types:

- `LayoutCache` keys an `Operation` type, a captured `Hashable` input, the effective `FittingProposal`, and a `Hashable` context (with no `version` parameter). On a miss, it passes the captured input, effective proposal, and context into a nonescaping synchronous calculation closure and never retains that closure. It imposes no text-measurement, rounding, clamping, or layout-scheduling policy.
- `FittingProposal(fitting:)` maps both `CGFloat.greatestFiniteMagnitude` and `+infinity` to `.unconstrained` and throws `FittingProposalError.invalidDimension` for NaN, `-infinity`, or negative dimensions. `FittingDimension(points:)` rejects both infinities, and `FittingProposal.fittingSize` maps `.unconstrained` back to `CGFloat.greatestFiniteMagnitude` while keeping finite dimensions exact.
- Multiple views may share a `LayoutCache` by reference, and composed parent keys (`LayoutCache.key(for:proposal:context:)`) preserve operation separation. Reentering a `LayoutCache` during its calculation closure—including reading `count`, removing an entry, or clearing—must fail a descriptive precondition.

### 8c. Text-component example

Keep example-specific text, font, and button policies in the non-product `DerivedKeysUIExample` target; built-in text-measurement wrappers and Auto Layout helpers are outside the library's scope.

Demonstrate a composite text component containing body text and an optional expansion button:

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

- Parent keys compose the children's dependency keys with parent-only inputs (`padding`, `spacing`, `showsButton`), while child size caches remain independently reusable.
- Select every input read by the sizing calculation—such as width, height bounds, font metrics, Dynamic Type category, locale, layout direction, line limits, paragraph spacing, attachments, padding, and display scale (if the recipe rounds to pixels)—without blindly selecting the entire `UITraitCollection`.
- The sizing cache must key the effective fitting proposal automatically; passing a width into measurement without keying it violates the contract.
- Represent unconstrained dimensions explicitly, reject NaN, `-infinity`, and negative dimensions at the boundary, and map framework sentinels (`CGFloat.greatestFiniteMagnitude` and `+infinity`) to the canonical unconstrained representation. If a recipe quantizes proposals, both the key and the measurement must use the same quantized value.
- Key the rendered text (or a projection of its metric-affecting attributes) rather than a bare document ID. An ID plus revision is valid only when every size-relevant mutation increments the revision and the pair uniquely identifies immutable content for the cache's lifetime.
- Omit action callbacks, analytics IDs, unrelated URLs, and paint-only colors that do not affect geometry. Toggling button visibility must change the component key even though it leaves the text child's key unchanged.
- View reuse must not depend on view instance identity: two distinct views with equal inputs share cached sizes, and a recycled view reconfigured with new inputs forms a new key.
- Updating model state, querying a cached size, calling `setNeedsLayout()`, and updating a container remain separate application steps.

### 8d. Configured arbitrary-result caches

Provide `ResultCache<Input, Value>` in `DerivedKeys` and `MainActorResultCache<Input, Value>` in `DerivedKeysUI`:

- **Initialization and surface:** Both bind a parameter pack of heterogeneous `Hashable` key paths on `Input`, an explicit local `capacity`, and one synchronous nonthrowing recipe closure at initialization. Lookups use `value(for:)`, per-entry removal uses `removeValue(for:)` with the current input's selected values, and both expose `count`, `capacity`, and `removeAll()` without exposing internal key types.
- **Dependency selection:** Only selected key paths enter the key. Both caches support nested key paths, zero key paths, `\.self` for a whole `Hashable` input, and named tuple inputs (where each relevant tuple element is selected by key path). `Input` and `Value` need not be `Hashable` or `Sendable`, while each selected value must be `Hashable` and stable while cached. Lookups evaluate every key path once before consulting the cache, then pass `Input` to the recipe on a miss.
- **Isolation and value vs reference semantics:** `ResultCache` is a non-`Sendable` value type whose copies mutate entries independently. It takes ordinary key paths and an ordinary recipe closure with no `@Sendable` or `Sendable` constraint, so Swift 6 region isolation confines an instance built from actor-isolated key paths or closures to that actor (allowing a `@MainActor` type to store a `ResultCache` directly). It relies on exclusive `inout` mutation, and same-cache reentry is unsupported. `MainActorResultCache` is a `@MainActor` reference type for shared main-actor ownership; it enforces a runtime reentry precondition across dependency reads, recipe calculation, `count` inspection, `removeValue(for:)`, and `removeAll()` (while `capacity` remains readable). Calling a distinct cache inside a recipe is allowed.
- **Storage and retention:** Both use the class-boxed `DependencySnapshot` representation and `MemoizationCache` LRU storage, preserving collision resistance, `Optional.none` hits, `capacity: 0`, LRU recency order, and local clearing. Each cache retains its recipe and key-path readers, and entries retain selected values and results without implicitly retaining the lookup `Input` (though recipe captures, reference-valued selections, and results can retain objects, and copying `ResultCache` does not deep-copy those objects).
- **Explicit staging:** Multi-stage calculations resolve one cache explicitly and pass its output into the next cache's input. Neither result cache performs automatic pipeline traversal, child-cache composition, `bound(to:)` root mapping, proposal normalization, or view invalidation.

In `DerivedKeysUIExample`, demonstrate a two-stage pipeline (`ResultBasedRowMeasurements`) that caches `(text, width, font) -> Int` line counts in a `MainActorResultCache` and then caches `PlainTextRowView` sizes in a `SizeCache` keyed by that line count, `font`, `horizontalPadding`, and `verticalPadding` (plus the automatic fitting proposal):

- Count actual TextKit line fragments under the same uniform plain-text font, natural line heights, and fixed paragraph settings as the rendered `PlainTextRowView`, including an empty string's single line and the trailing empty line after a final newline. Require a finite positive inner width and reject unconstrained width.
- On a row-size miss, fill the supplied width and call the private text view's `sizeThatFits(_:)` for height rather than multiplying line count by a font metric. Keep the text view synchronized with the model string, select native model strings, bound each stage's capacity independently, and avoid capturing the owning container.
- Document that equal line counts imply equal height only under this uniform plain-text rendering policy and fixed inner width, not for arbitrary rich text or variable line spacing, and that counting lines runs TextKit layout (so callers must measure the full two-stage request before assuming a speedup). Also demonstrate a non-UI `ResultCache` for tokenized search text.
- Validate selected and unselected input changes, scalar/nested/zero/tuple key paths, projected value snapshots, hash collisions, `Optional.none` hits, LRU eviction, `capacity: 0`, clearing, `ResultCache` copy independence, `MainActorResultCache` shared ownership, input release, and reentry preconditions; compile positive and negative Swift 6 concurrency fixtures (including iOS 16 UIKit key paths); and test line-count invalidation, cross-string row-size reuse when line counts match, and exact agreement with direct `UITextView` fitting across empty, multiline, trailing-newline, and multilingual strings.

## 9. Non-UI example

Provide a runnable non-UI example (`DocumentExportExample`) that uses the generic key types and `MemoizationCache`:

```text
export key
  ├─ ordered projected document content
  ├─ export format
  ├─ relevant export options
  ├─ locale, if used
  └─ exporter algorithm version, if needed
```

- Exclude UI-only state such as selection, scroll offset, view size, and share callbacks.
- Changing an export option must miss and recompute; changing an unselected UI property must hit and reuse the cached output.
- The target must build and run using only `DerivedKeys` and the Swift standard library, without importing UIKit, AppKit, SwiftUI, or CoreGraphics.

## 10. Performance requirements

### Key and storage costs

Measure key construction, hashing, and lookup overhead separately from the cached computation itself:

- Avoid heap allocations on repeated lookups when static generic key types (`RequestKey`, `KeyPair`, `OriginalKey`, `DerivedKey`) suffice.
- Build composite `KeySource` child lists in linear time via the bulk initializer (`init(_:children:)`) so callers do not pay quadratic copying costs from repeated `appending(_:)` calls.
- Avoid rereading or rehashing large immutable payloads unnecessarily; callers can precompute projections at mutation boundaries or use an ID-and-revision pair when backed by an explicit mutation-coverage and non-reuse contract (never a truncated integer hash).
- Use request-local memoization in `KeySource.snapshot(for:)` so shared source nodes run their providers only once per snapshot, and enforce the 64-node maximum depth.
- Bound cache entry counts (`capacity`) and account for memory retained by both keys and results, avoiding accidental retention of large model owners inside small projections.
- Document that lookup time includes projection, hashing, and key equality proportional to the selected data, while hash-table lookup and LRU list updates take expected amortized constant time beyond those key costs.
- Use standard-library collections and generics without macros or external dependencies unless benchmark evidence justifies added machinery.
- Erase leaf values in `DependencySnapshot` with a private generic class box that preserves the concrete value type's identity, `==`, and `hash(into:)`—never `AnyHashable`—and share that representation across direct snapshots, `KeySource`, `ResultCache`, and `DerivedKeysUI` without requiring caller wrappers.
- Mark the core's hot generic entry points (`MemoizationCache`, typed keys, `KeyProjection.key`, `DependencySnapshot.init(value:)`, and `ResultCache` lookup and removal) `@inlinable` with explicit typed-key `==` and `hash(into:)` implementations so client modules specialize them. Any change to snapshot representation or inlining requires both correctness tests and benchmark evidence.

### Benchmark coverage

Provide reproducible Release benchmarks covering direct computation, cold misses, warm hits, relevant-input mutations, irrelevant-input mutations, small and large payloads, shared dependency nodes, and bounded LRU eviction. Record the compiler, host hardware, OS/SDK versions, workload parameters, key overhead, calculation counts, and timing distributions, without claiming a universal speedup ratio.

For UI sizing, real `@MainActor` UIKit fitting (`UILabel`, `UITextView`, `UIButton`, and composed `DocumentContentView`) is the primary benchmark evidence:

- Compare cached sizing against an equivalent direct UIKit baseline that preserves UIKit's own warmed internal layout state.
- Cover warm unchanged views, equivalent view pools, warm composed parents, parent-only spacing changes, outer width changes, content/typography changes, and bounded mixed traces that exercise hits, misses, and eviction.
- Separate measurement-only scenarios from scenarios that include view configuration inside the timed loop, verify output equality and hit/miss counts outside timing, and report medians and trial variability across repeated runs.
- Report iOS Simulator and physical-device timings separately, and keep synthetic macOS benchmarks (`DerivedKeysBenchmarks`) as secondary component diagnostics—fewer `sizeThatFits(_:)` calls alone do not establish a wall-clock speedup.

## 11. Acceptance criteria and deliverables

The test suite must deterministically verify every scenario below:

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

Never test inequality by asserting `lhs.hashValue != rhs.hashValue`; test semantic `==` and deliberate hash collisions instead.

Include positive compilation fixtures for valid Swift 6 concurrency usage (including a `@MainActor` type owning a `ResultCache`) and negative fixtures for rejected cross-task transfers (such as sending that `ResultCache` to a detached task) compiled under the package's exact Swift 6 and warnings-as-errors flags.

Deliverables:

- The `DerivedKeys` Swift package module with typed keys, `KeyProjection`, `KeySource`, `DependencySnapshot`, `MemoizationCache`, and `ResultCache`.
- The `DerivedKeysUI` product with `SizeCache`, `SizeCacheBinding`, `SizeDependencies`, `MainActorResultCache`, `LayoutCache`, and `FittingProposal`, plus the tested UIKit examples in `DerivedKeysUIExample`.
- The runnable `DocumentExportExample` target.
- Public DocC and Markdown documentation covering equality, dependency completeness, evaluation timing, actor isolation, retention, and complexity.
- Automated unit, precondition, concurrency, Simulator, and DocC validation scripts, plus reproducible Release benchmarks.
- Documented local check commands, benchmark results, and any known environment constraints (such as tool-hosted XCTest requiring an app host on physical iOS devices).

The package meets this specification when all requirements above are implemented and the full validation suite passes; any unverified environment or gap must be reported explicitly.
