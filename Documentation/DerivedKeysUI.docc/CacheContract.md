# The cache contract

How DerivedKeys caches reuse results and what callers must uphold.

## Overview

A cache reuses a result when the selected values match a retained entry. Because the cache compares only what you select and cannot inspect what a recipe reads, reuse is correct only when your selection is complete. These rules apply across ``SizeCache``, ``MainActorResultCache``, ``LayoutCache``, and the `DerivedKeys` module's `ResultCache` and `MemoizationCache`.

## Select every variable input

Select every value that the recipe reads and that can vary between requests. Include values used to transform a proposal, branch, or combine child results, along with environment inputs such as fonts, traits, or locale. Selecting an unused value only costs cache hits; omitting a value that affects the output can return a wrong result.

Any setting the recipe reads that you do not select must stay fixed for the cache's lifetime and match across every root sharing the cache. If a setting can vary, select it or use a separate cache. An empty selection gives every request the same key, so use it only when the result cannot vary with the input.

During a synchronous lookup, dependency getters and the recipe must observe a consistent state. Dependency getters must not mutate result-relevant state, perform I/O, or evaluate caches recursively. Because a hit skips the recipe, any side effect that must happen on every request belongs outside it. A cache does not observe model changes, schedule layout, or refit a container; your code does that after inputs change.

## Select stable values

Conforming to `Hashable` does not make a mutable reference type a snapshot. If a class instance mutates after the cache stores it, its hash and equality change behind the cache's back. Select immutable values, or expose a computed property that projects an immutable snapshot and select that key path.

An object identity or document ID alone does not track changing content. Pairing an ID with a revision works only if every size- or result-relevant change updates the revision and the pair is never reused for different content while cached entries may remain.

Keys retain complete values, their concrete types, and their ordered structure. Because lookup always compares the complete key after hashing, a hash collision cannot substitute one result for another. Swift `Hasher` output is process-local; do not persist it or treat it as a stable identifier.

## What a cache retains

A cache retains its configured recipe (including anything the recipe captures), its key-path readers, the selected values, and the cached results. It does not implicitly retain the root or input passed to a lookup.

Captured owners, reference-valued dependencies, and results can still keep objects alive. Do not let a recipe strongly capture the object that owns the cache, which creates a reference cycle. A ``SizeCacheBinding`` retains its original cache, whereas listing a child in `children:` retains only that child's dependency readers—the parent's recipe must capture the child handles it calls.

Copying a value-type `ResultCache` or `MemoizationCache` copies its entries independently without deep-copying the objects they reference.

## Reentrancy

Calling the same cache while its recipe is running is unsupported. The main-actor caches (``SizeCache``, ``MainActorResultCache``, and ``LayoutCache``) fail a descriptive precondition on any reentry, including reading `count`, removing entries, clearing, or calling through an alias or binding. The value-type caches (`ResultCache` and `MemoizationCache`) require exclusive mutable access, so reentry is unsupported and has no defined result. Calling a distinct cache inside a recipe is supported and is how a parent measures through its children.

Watch for indirect reentry with UIKit leaf caches. The ``SizeCache`` UIKit initializer calls the view's `sizeThatFits(_:)` on a miss. If that view's `sizeThatFits(_:)` override calls the same cache, a miss reenters the cache and traps. To cache a custom view's `sizeThatFits(_:)`, use the closure initializer with a recipe that measures child caches or calls a separate uncached helper; a recipe that calls the cached override still reenters.

## Fitting proposals

``SizeCache`` and ``LayoutCache`` add the effective fitting proposal to every key automatically; you do not select it. ``MainActorResultCache`` and `ResultCache` do not key or validate a proposal, so select any dimensions those recipes use.

- **Exact finite dimensions.** Both axes are keyed without rounding. Signed zero (`-0.0`) normalizes to `0.0`, and the recipe receives the normalized proposal that the key describes.
- **Unconstrained axes.** Both `CGFloat.greatestFiniteMagnitude` and positive infinity mean an unconstrained axis. ``FittingProposal/init(fitting:)`` maps both to ``FittingDimension/unconstrained``, and the recipe receives `CGFloat.greatestFiniteMagnitude` for either.
- **Invalid dimensions.** NaN, negative infinity, and negative values fail: ``SizeCache`` fails a precondition, and ``FittingProposal/init(fitting:)`` throws ``FittingProposalError/invalidDimension``. ``FittingDimension/init(points:)`` rejects infinity because ``FittingDimension/unconstrained`` represents an unbounded axis.
- **Unmodified results.** Results are stored exactly as the recipe returns them. Rounding and clamping belong in the recipe.

In a composed layout, a parent keys its outer proposal and its own selected values, while each child keys the proposal it actually receives. Transform proposals inside the parent's recipe and select the values that drive the transform.

## Declare children

A parent ``SizeCache`` declares its children in `children:` and captures those same handles in its recipe. Use ``SizeCache/bound(to:)`` to map a child cache onto a parent root of a different type.

Every declared child contributes its selected values to the parent's key on every lookup, even when a branch in the recipe skips measuring it. A parent hit skips the recipe and every child lookup. Child sizes and child eviction state never enter the parent key, so clearing or evicting a child does not invalidate a parent entry.

A parent that measured through an undeclared cache would return stale hits when only that child's inputs changed. In debug builds, any ``SizeCache`` lookup made while another size cache's recipe is running asserts unless the nearest running parent declared that cache, either directly in `children:` or transitively through a declared child:

- A lookup through a ``SizeCacheBinding`` rooted at the running parent must also match a declared path; declaring a title binding and measuring a subtitle binding of the same cache fails.
- A lookup that calls a ``SizeCache`` directly, or uses a binding rooted at a different type, has no comparable path and is checked by cache identity only.
- Pass `allowsUndeclaredMeasurements: true` to a parent whose recipe measures a fixed captured root that no key path from the parent root can reach; you then own the completeness of that parent's selection.
- The native UIKit initializer is exempt because the view's `sizeThatFits(_:)` is opaque to the cache. Release builds omit the check and its bookkeeping, and lookups on ``MainActorResultCache``, ``LayoutCache``, and `ResultCache` are never checked.

A composed dependency description is immutable and acyclic by construction. ``SizeDependencies/maximumDepth`` reports the checked limit of 64 snapshot nodes on any root-to-leaf path: an empty description has depth 1, a description with selected values has depth 2, each parent adds 1 level, and mapping with ``SizeCache/bound(to:)`` adds none. Exceeding 64 fails a precondition.

## Capacity, eviction, and clearing

Capacity limits the number of entries in one cache, not bytes; large keys and results retain proportionally more memory. A capacity of `0` disables storage while still running the recipe. For positive capacities, hits and insertions update recency, and a full cache evicts its least recently used entry. Returning to an earlier input reuses its entry if it is still retained. Choose a capacity for the distinct states you expect to revisit before eviction.

Each cache evicts and clears independently, with no recursive clearing and no shared eviction budget. Clearing a parent leaves its children intact, and clearing or evicting a child leaves valid parent entries intact. If a change you did not select invalidates cached results, clear every affected cache or select that change as a dependency.

Bindings expose measurement only; inspect `count` and clear entries on the original ``SizeCache``.

## Isolation

``SizeCache``, ``MainActorResultCache``, and ``LayoutCache`` are `@MainActor` reference types. Sharing a reference shares its entries and recency order.

The generic `DerivedKeys` module uses ordinary key paths and closures with no `Sendable` requirement, and its cache, source, snapshot, and projection types are not `Sendable`. Swift 6 region isolation keeps an instance built from main-actor key paths or closures confined to the main actor, so a `@MainActor` type can own a `ResultCache` directly and sending it to another task fails at compile time. Use ``MainActorResultCache`` when you want a shared main-actor reference with the reentry check. Inputs, roots, and results never need to be `Sendable`.
