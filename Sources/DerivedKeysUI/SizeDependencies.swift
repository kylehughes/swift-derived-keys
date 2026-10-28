import DerivedKeys

/// An immutable description of the values consumed by a size calculation.
///
/// Descriptions capture complete values and ordered child structure, without observing
/// roots or retaining them implicitly. Hashable projections must remain semantically
/// stable while cached. Each occurrence is evaluated independently, including repeated
/// mappings of one description. Construction is closed to external subclasses.
@MainActor
public class SizeDependencies<Root> {
    /// The maximum depth of a captured dependency snapshot.
    public static var maximumDepth: Int { DependencySnapshot.maximumDepth }

    let capture: (Root) -> DependencySnapshot
    let depth: Int

    init(depth: Int, capture: @escaping (Root) -> DependencySnapshot) {
        self.capture = capture
        self.depth = depth
    }

    /// Maps this description onto a nested root without adding snapshot structure.
    ///
    /// The returned description retains the immutable capture recipe, not this cache's
    /// result storage or measurement closure. Mapping does not increase dependency depth.
    public func at<Parent>(_ path: KeyPath<Parent, Root>) -> SizeDependencies<Parent> {
        let capture = capture
        return SizeDependencies<Parent>(depth: depth) { root in
            capture(root[keyPath: path])
        }
    }

    /// Captures the described values and ordered structure without measuring or changing recency.
    ///
    /// Snapshots exclude the fitting proposal and measurement recipe identity, so a snapshot
    /// alone is not a complete size-result key. Cost is linear in the described graph and
    /// projected value work; repeated child occurrences are evaluated separately.
    public func snapshot(of root: Root) -> DependencySnapshot {
        capture(root)
    }
}
