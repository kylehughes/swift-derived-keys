/// An immutable description of how to read a heterogeneous set of dependencies from an input.
///
/// A source is not `Hashable`: evaluate it into a ``DependencySnapshot`` before a dictionary
/// lookup. Independent graphs with equal labels, concrete value types, structure, and captured
/// values produce equal snapshots. Node identity is used only to evaluate each shared node once
/// per call to ``snapshot(for:)``.
///
/// Providers are ordinary closures that run synchronously and must be side-effect-free reads;
/// see <doc:DependencyDesign>. A source retains its providers. It is not `Sendable`, so Swift 6
/// region isolation confines a source built from actor-isolated closures to that actor. Input
/// and value types need not be `Sendable`.
public struct KeySource<Input> {
    /// The largest supported number of nodes on a root-to-leaf path.
    ///
    /// The bound keeps recursive evaluation, equality, hashing, and teardown safe.
    public static var maximumDepth: Int {
        DependencySnapshot.maximumDepth
    }

    private let node: Node

    /// Creates a source for one labeled immutable value.
    public init<Value>(_ label: String, value: Value) where Value: Hashable {
        node = Node(
            label: label,
            kind: .original { _ in
                DependencySnapshot(label: label, value: value)
            },
            depth: 1
        )
    }

    /// Creates a source whose provider closure runs on each evaluation.
    ///
    /// A shared source is read once per evaluation. The returned value must be an immutable
    /// snapshot, not a mutable reference.
    public init<Value>(_ label: String, provider: @escaping (Input) -> Value) where Value: Hashable {
        node = Node(
            label: label,
            kind: .original { input in
                DependencySnapshot(label: label, value: provider(input))
            },
            depth: 1
        )
    }

    /// Creates a labeled, ordered composition of sources in one pass.
    ///
    /// An empty composition is valid. Children keep their boundaries and labels.
    /// - Throws: ``ConstructionError/maximumDepthExceeded`` for a path longer than
    ///   ``maximumDepth``.
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

    /// Returns this composition with one more child at the end.
    ///
    /// The original is unchanged. Build a large list with ``init(_:children:)`` instead;
    /// repeated appends copy the list and can cost O(n²) overall.
    /// - Throws: ``ConstructionError/notDerived`` for an original source, or
    ///   ``ConstructionError/maximumDepthExceeded`` for an unsupported depth.
    public func appending(_ child: Self) throws -> Self {
        guard case .derived(let children) = node.kind else {
            throw ConstructionError.notDerived
        }

        return try Self(node.label, children: children.map { Self(node: $0) } + [child])
    }

    /// Reads the dependencies from `input` into a snapshot.
    ///
    /// Each shared node is read at most once per call. Later calls read again, and an existing
    /// snapshot never runs a provider again. Reads are not atomic, so keep the input state
    /// consistent for the whole request.
    /// - Parameter input: The captured input to read.
    /// - Returns: The values and structure of the graph.
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
    /// An error from composing a source.
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
