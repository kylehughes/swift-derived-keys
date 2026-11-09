import DerivedKeys

/// An immutable description of the selected values a size recipe reads from a root.
///
/// ``SizeCache`` and ``SizeCacheBinding`` are the only concrete descriptions; pass them in a
/// parent's `children:` list. You cannot subclass `SizeDependencies` outside the module. A
/// description captures complete values and ordered child structure from a root on demand
/// without retaining the root, and evaluates each child occurrence separately—including repeated
/// bindings of one cache; see <doc:CacheContract>.
@MainActor
public class SizeDependencies<Root> {
    /// The maximum number of snapshot nodes on any path of a description.
    public static var maximumDepth: Int { DependencySnapshot.maximumDepth }

    let capture: (Root) -> DependencySnapshot
    let depth: Int
    let childDeclarations: SizeDeclarations

    /// The caches this description declares to a parent, used by the debug declared-children check.
    var declarations: SizeDeclarations { childDeclarations }

    init(depth: Int, declarations: SizeDeclarations, capture: @escaping (Root) -> DependencySnapshot) {
        self.capture = capture
        self.depth = depth
        childDeclarations = declarations
    }

    // Release builds must not evaluate declarations at all: they exist only for the debug check.
    func rebasedDeclarations<Parent>(
        of declarations: @autoclosure () -> SizeDeclarations,
        onto path: KeyPath<Parent, Root>
    ) -> SizeDeclarations {
        #if DEBUG
        declarations().rebased(onto: path)
        #else
        .none
        #endif
    }

    /// Captures the described values and structure without measuring or changing recency.
    ///
    /// The snapshot excludes the fitting proposal, so it is not a complete result key.
    /// - Parameter root: The current root whose selected values are captured.
    /// - Returns: The selected values and their structure.
    /// - Complexity: Linear in the described graph plus the work of reading each value.
    public func snapshot(of root: Root) -> DependencySnapshot {
        capture(root)
    }
}
