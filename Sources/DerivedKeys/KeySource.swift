/// An immutable recipe for evaluating a heterogeneous dependency graph.
///
/// Sources are not Hashable. Evaluate them into ``DependencySnapshot`` before a
/// dictionary lookup. Independent graphs with equal labels, concrete value types,
/// structure, and captured values produce equal snapshots; node identity is used
/// only to capture each shared leaf once per evaluation.
///
/// Prefer immutable explicit inputs. Providers are synchronous nonisolated reads;
/// they must not mutate inputs, perform I/O, or recursively evaluate the graph.
/// Use a ``KeyValueProvider`` for live non-Sendable state. Closure convenience
/// providers are Sendable so they cannot erase actor isolation. A source retains
/// its provider for its lifetime. Capture actor state outside the provider
/// and pass the resulting snapshot as input. Input and returned value types need
/// not be Sendable.
public struct KeySource<Input> {
    /// The largest supported number of nodes on a root-to-leaf path.
    ///
    /// This bound protects recursive evaluation, equality, hashing, and teardown.
    public static var maximumDepth: Int {
        DependencySnapshot.maximumDepth
    }

    private let node: Node

    /// Creates an original source from an immutable value.
    public init<Value>(_ label: String, value: Value) where Value: Hashable {
        node = Node(
            label: label,
            kind: .original { _ in
                DependencySnapshot(label: label, value: value)
            },
            depth: 1
        )
    }

    /// Creates an original source whose provider runs on each evaluation.
    ///
    /// Each shared source is read once per evaluation. The returned value
    /// must be an immutable snapshot, not a mutable reference used for hashing.
    public init<Value>(_ label: String, provider: @escaping @Sendable (Input) -> Value) where Value: Hashable {
        node = Node(
            label: label,
            kind: .original { input in
                DependencySnapshot(label: label, value: provider(input))
            },
            depth: 1
        )
    }

    /// Creates an original source from a nonisolated, possibly non-Sendable reader.
    ///
    /// The source retains the provider, but evaluated snapshots do not. Keep
    /// provider-owned mutable state within one owner and return immutable values.
    public init<Provider>(_ label: String, provider: Provider)
    where Provider: KeyValueProvider, Provider.Input == Input {
        node = Node(
            label: label,
            kind: .original { input in
                DependencySnapshot(label: label, value: provider.value(for: input))
            },
            depth: 1
        )
    }

    /// Creates a derived source from an ordered collection in one pass.
    ///
    /// Empty compositions are valid. Children retain their boundaries and labels.
    /// - Throws: ``ConstructionError/maximumDepthExceeded`` for a path longer than
    ///   ``maximumDepth``. Immutable construction cannot introduce graph cycles.
    /// - Complexity: O(n) in the number of immediate children.
    public init(_ label: String, children: [Self]) throws {
        var nodes: [Node] = []
        nodes.reserveCapacity(children.count)
        var depth = 1
        for child in children {
            depth = max(depth, child.node.depth + 1)
            nodes.append(child.node)
        }
        guard depth <= Self.maximumDepth else {
            throw ConstructionError.maximumDepthExceeded
        }

        node = Node(label: label, kind: .derived(nodes), depth: depth)
    }

    /// Returns a derived composition with one more ordered child.
    ///
    /// The original composition is unchanged. Use ``init(_:children:)`` to build
    /// a large list; repeated appends copy that list and can cost O(n²) overall.
    /// - Throws: ``ConstructionError/notDerived`` for an original source, or
    ///   ``ConstructionError/maximumDepthExceeded`` for an unsupported depth.
    public func appending(_ child: Self) throws -> Self {
        guard case .derived(let children) = node.kind else {
            throw ConstructionError.notDerived
        }

        return try Self(node.label, children: children.map { Self(node: $0) } + [child])
    }

    /// Captures every distinct source once from one coherent input state.
    ///
    /// Memoization is request-local. Previously evaluated keys cannot trigger
    /// providers again. Capturing related mutable properties individually is not
    /// an atomic snapshot; callers are responsible for consistency across the complete request.
    /// - Complexity: O(v + e) visits for v nodes and e edges, plus provider work.
    ///   Result equality and hashing inspect values and repeated child occurrences.
    public func snapshot(for input: Input) -> DependencySnapshot {
        var captured: [ObjectIdentifier: DependencySnapshot] = [:]
        return node.snapshot(for: input, captured: &captured)
    }

    private init(node: Node) {
        self.node = node
    }
}

extension KeySource {
    /// An invalid composition request.
    public enum ConstructionError: Error, Equatable {
        /// The new graph would exceed the supported depth.
        case maximumDepthExceeded
        /// Appending requires a derived composition.
        case notDerived
    }
}

extension KeySource {
    private final class Node {
        enum Kind {
            case original((Input) -> DependencySnapshot)
            case derived([Node])
        }

        let depth: Int
        let kind: Kind
        let label: String

        init(label: String, kind: Kind, depth: Int) {
            self.label = label
            self.kind = kind
            self.depth = depth
        }

        func snapshot(for input: Input, captured: inout [ObjectIdentifier: DependencySnapshot]) -> DependencySnapshot {
            let identity = ObjectIdentifier(self)
            if let existing = captured[identity] {
                return existing
            }

            let result: DependencySnapshot
            switch kind {
            case .original(let provider):
                result = provider(input)
            case .derived(let children):
                result = DependencySnapshot(
                    node: .derived(
                        label: label,
                        children: children.map {
                            $0.snapshot(for: input, captured: &captured)
                        }
                    )
                )
            }
            captured[identity] = result

            return result
        }
    }
}
