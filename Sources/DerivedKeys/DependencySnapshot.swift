/// An evaluated heterogeneous source graph with structural equality.
///
/// Snapshots contain captured values and structure, never provider closures or
/// graph nodes. Captured values must have stable equality and hashing; mutable
/// references require an explicit immutable projection. The erased representation
/// deliberately has no Sendable conformance. Prefer typed keys for transferable values.
public struct DependencySnapshot: Hashable {
    let node: Node
}

extension DependencySnapshot {
    indirect enum Node: Hashable {
        case original(label: String, type: ObjectIdentifier, value: AnyHashable)
        case derived(label: String, children: [DependencySnapshot])
    }
}
