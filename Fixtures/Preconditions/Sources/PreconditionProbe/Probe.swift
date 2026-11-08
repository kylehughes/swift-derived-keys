import CoreGraphics
import DerivedKeysUI

@main
@MainActor
struct PreconditionProbe {
    final class Root {
        var value = 1
    }

    @MainActor
    final class ReentryState {
        var cache: SizeCache<Root>!
        var shouldReenter = false
    }

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { fatalError("Expected one named probe") }
        let name = arguments[1]
        if name.hasPrefix("result-") {
            ResultCacheProbes.run(name)
            print("Completed \(name)")
            return
        }
        let root = Root()
        let proposal = CGSize(width: 100, height: 20)
        switch name {
        case "valid-dimensions":
            let cache = SizeCache<Root>(capacity: 1) { _, size in size }
            for dimension in [CGFloat.zero, -CGFloat.zero, CGFloat.greatestFiniteMagnitude] {
                let size = CGSize(width: dimension, height: dimension)
                precondition(cache.size(of: root, toFit: size) == size)
                cache.removeSize(of: root, toFit: size)
            }
        case "negative-capacity":
            _ = SizeCache<Root>(capacity: -1) { _, size in size }
        case "depth-64", "depth-65", "leaf-depth-64", "leaf-depth-65":
            let hasLeaf = name.hasPrefix("leaf-")
            let targetDepth = name.hasSuffix("65") ? 65 : 64
            var cache =
                hasLeaf
                ? SizeCache<Root>(dependingOn: \.value, capacity: 1) { _, size in size }
                : SizeCache<Root>(capacity: 1) { _, size in size }
            let initialDepth = hasLeaf ? 2 : 1
            for _ in initialDepth ..< targetDepth {
                cache = SizeCache<Root>(children: cache, capacity: 1) { _, size in size }
            }
            _ = cache.snapshot(of: root)
            _ = cache.size(of: root, toFit: proposal)
        case "distinct-cache-nesting":
            let child = SizeCache<Root>(capacity: 1) { _, size in size }
            let parent = SizeCache<Root>(children: child, capacity: 1) { root, size in
                child.size(of: root, toFit: size)
            }
            precondition(parent.size(of: root, toFit: proposal) == proposal)
        case "reentry", "warm-hit-reentry", "count-reentry", "remove-reentry", "remove-all-reentry", "bound-reentry":
            let state = ReentryState()
            state.cache = SizeCache<Root>(dependingOn: \.value, capacity: 2) { root, size in
                if state.shouldReenter {
                    let alias = state.cache!
                    switch name {
                    case "bound-reentry":
                        _ = alias.bound(to: \Root.self).bound(to: \Root.self).size(of: root, toFit: size)
                    case "count-reentry": _ = alias.count
                    case "remove-reentry": alias.removeSize(of: root, toFit: size)
                    case "remove-all-reentry": alias.removeAll()
                    default:
                        root.value = 1
                        _ = alias.size(of: root, toFit: size)
                    }
                }
                return size
            }
            if name == "warm-hit-reentry" {
                _ = state.cache.size(of: root, toFit: proposal)
                root.value = 2
            }
            state.shouldReenter = true
            _ = state.cache.size(of: root, toFit: proposal)
        default:
            let pieces = name.split(separator: "-")
            guard pieces.count == 3, ["size", "remove", "bound"].contains(pieces[0]),
                ["width", "height"].contains(pieces[1])
            else {
                fatalError("Unknown probe: \(name)")
            }
            let invalid: CGFloat
            switch pieces[2] {
            case "nan": invalid = .nan
            case "infinity": invalid = .infinity
            case "negativeInfinity": invalid = -.infinity
            case "negative": invalid = -1
            default: fatalError("Unknown dimension: \(pieces[2])")
            }
            let size =
                pieces[1] == "width"
                ? CGSize(width: invalid, height: 20) : CGSize(width: 100, height: invalid)
            let cache = SizeCache<Root>(capacity: 1) { _, size in size }
            if pieces[0] == "size" {
                _ = cache.size(of: root, toFit: size)
            } else if pieces[0] == "bound" {
                _ = cache.bound(to: \Root.self).size(of: root, toFit: size)
            } else {
                cache.removeSize(of: root, toFit: size)
            }
        }
        print("Completed \(name)")
    }
}
