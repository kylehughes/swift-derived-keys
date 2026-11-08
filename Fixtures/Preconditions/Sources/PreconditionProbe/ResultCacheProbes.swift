import DerivedKeys
import DerivedKeysUI

@MainActor
enum ResultCacheProbes {
    @MainActor
    final class Input {
        var onRead: (() -> Void)?
        var value = 1

        var selected: Int {
            onRead?()
            return value
        }
    }

    @MainActor
    final class State {
        var cache: MainActorResultCache<Input, Int>!
        var onCompute: (() -> Void)?
    }

    static func run(_ name: String) {
        switch name {
        case "result-valid":
            var core = ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 * 2 }
            precondition(core.value(for: 3) == 6)
            core.removeValue(for: 3)
            precondition(core.count == 0)
            let state = State()
            state.cache = MainActorResultCache(dependingOn: \.selected, capacity: 2) { input in
                precondition(state.cache.capacity == 2)
                return input.value
            }
            precondition(state.cache.value(for: Input()) == 1)
            precondition(state.cache.count == 1)
            state.cache.removeAll()
            precondition(state.cache.count == 0)
        case "result-negative-capacity":
            _ = MainActorResultCache<Int, Int>(capacity: -1) { $0 }
        case "result-core-negative-capacity":
            _ = ResultCache<Int, Int>(capacity: -1) { $0 }
        case "result-distinct-cache-nesting":
            let child = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 * 2 }
            let parent = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 1) {
                child.value(for: $0) + 1
            }
            precondition(parent.value(for: 3) == 7)
            precondition(parent.count == 1 && child.count == 1)
        default:
            let parts = name.split(separator: "-")
            precondition(parts.count == 3)
            let input = Input()
            let state = State()
            state.cache = MainActorResultCache(dependingOn: \.selected, capacity: 2) { input in
                state.onCompute?()
                return input.value
            }
            // A retained entry also exercises reentry that would otherwise hit warm storage.
            precondition(state.cache.value(for: input) == 1)
            let reenter: () -> Void = {
                switch parts[2] {
                case "lookup":
                    input.value = 1
                    _ = state.cache.value(for: input)
                case "count": _ = state.cache.count
                case "remove": state.cache.removeValue(for: input)
                case "clear": state.cache.removeAll()
                default: fatalError("Unknown result-cache reentry operation")
                }
            }
            switch parts[1] {
            case "compute":
                input.value = 2
                state.onCompute = reenter
                _ = state.cache.value(for: input)
            case "capture":
                input.onRead = reenter
                _ = state.cache.value(for: input)
            case "removal":
                input.onRead = reenter
                state.cache.removeValue(for: input)
            default: fatalError("Unknown result-cache reentry phase")
            }
        }
    }
}
