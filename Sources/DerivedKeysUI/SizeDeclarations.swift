/// One size cache reachable from a description's root, used only by the debug declared-children check.
struct SizeDeclaration: Hashable {
    let cache: ObjectIdentifier
    /// The path from the description's root to the cache's root; `nil` when they are the same root.
    let path: AnyKeyPath?
}

/// The caches a description declares, including those its children declare.
///
/// Release builds store nothing, so descriptions carry no extra state outside debugging.
struct SizeDeclarations {
    #if DEBUG
    var entries: Set<SizeDeclaration> = []
    #endif

    static var none: Self { Self() }

    static func cache(_ cache: ObjectIdentifier) -> Self {
        #if DEBUG
        Self(entries: [SizeDeclaration(cache: cache, path: nil)])
        #else
        Self()
        #endif
    }

    func union(_ other: Self) -> Self {
        #if DEBUG
        Self(entries: entries.union(other.entries))
        #else
        self
        #endif
    }

    func rebased<Parent, Root>(onto path: KeyPath<Parent, Root>) -> Self {
        #if DEBUG
        Self(
            entries: Set(
                entries.map { entry in
                    guard let existing = entry.path else {
                        return SizeDeclaration(cache: entry.cache, path: path)
                    }
                    guard let joined = (path as AnyKeyPath).appending(path: existing) else {
                        preconditionFailure("A size binding's path must end at its child description's root.")
                    }
                    return SizeDeclaration(cache: entry.cache, path: joined)
                }
            )
        )
        #else
        self
        #endif
    }
}

#if DEBUG
/// The declared children of each size recipe currently running, innermost last.
@MainActor
enum DeclaredChildren {
    private struct Frame {
        let declared: Set<SizeDeclaration>
        let root: ObjectIdentifier
        let allowsUndeclared: Bool
    }

    private static let message = "SizeCache measured through a child that its parent did not declare in children:."
    private static var frames: [Frame] = []
    private static var pendingBinding: SizeDeclaration?

    /// Records the binding a lookup is about to go through, so the cache can compare its path.
    static func noteBinding(_ target: SizeDeclarations) {
        pendingBinding = target.entries.first
    }

    /// Checks a lookup against the innermost running recipe's declared children.
    ///
    /// A lookup through a binding rooted at the parent's root must match a declared path. Other
    /// lookups carry no comparable path, so only the cache's identity is checked.
    static func check(_ cache: ObjectIdentifier) {
        let binding = pendingBinding
        pendingBinding = nil
        guard let frame = frames.last, !frame.allowsUndeclared else { return }
        let isDeclared: Bool
        if let binding, let path = binding.path, ObjectIdentifier(type(of: path).rootType) == frame.root {
            isDeclared = frame.declared.contains(binding)
        } else {
            isDeclared = frame.declared.contains { $0.cache == cache }
        }
        if !isDeclared {
            assertionFailure(message)
        }
    }

    static func push(_ declared: SizeDeclarations, root: ObjectIdentifier, allowsUndeclared: Bool) {
        frames.append(Frame(declared: declared.entries, root: root, allowsUndeclared: allowsUndeclared))
    }

    static func pop() {
        frames.removeLast()
    }
}
#endif
