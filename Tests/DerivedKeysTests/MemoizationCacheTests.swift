import DerivedKeys
import Testing

@Suite("Memoization cache")
struct MemoizationCacheTests {
    @Test
    func capacityAndHits() {
        var cache = MemoizationCache<String, Int>(capacity: 2)
        var computations = 0
        #expect(cache.capacity == 2)
        #expect(cache.count == 0)
        let first = cache.value(for: "a") {
            computations += 1
            return 17
        }
        let second = cache.value(for: "a") {
            computations += 1
            return 99
        }
        #expect(first == 17)
        #expect(second == 17)
        #expect(computations == 1)
        #expect(cache.count == 1)
    }

    @Test
    func collisionsUseEquality() {
        var cache = MemoizationCache<CollidingKey, Int>(capacity: 2)
        #expect(
            cache.value(for: CollidingKey(value: 1)) {
                10
            } == 10
        )
        #expect(
            cache.value(for: CollidingKey(value: 2)) {
                20
            } == 20
        )
        #expect(
            cache.value(for: CollidingKey(value: 1)) {
                -1
            } == 10
        )
        #expect(
            cache.value(for: CollidingKey(value: 2)) {
                -1
            } == 20
        )
    }

    @Test
    func copiesMutateIndependently() {
        var original = MemoizationCache<Int, Int>(capacity: 2)
        _ = original.value(for: 1) {
            10
        }
        _ = original.value(for: 2) {
            20
        }
        var copy = original
        _ = copy.value(for: 1) {
            -1
        }
        _ = copy.value(for: 3) {
            30
        }
        #expect(
            original.value(for: 2) {
                -1
            } == 20
        )
        #expect(
            copy.value(for: 2) {
                200
            } == 200
        )
        original.removeAll()
        #expect(original.count == 0)
        #expect(copy.count == 2)
        #expect(
            copy.value(for: 3) {
                -1
            } == 30
        )
    }

    @Test
    func doesNotRetainComputeCapture() {
        var cache = MemoizationCache<Int, Int>(capacity: 1)
        var owner: ObjectKey? = ObjectKey()
        weak let weakOwner = owner
        if let owner {
            _ = cache.value(for: 1) {
                withExtendedLifetime(owner) {
                    42
                }
            }
        }

        owner = nil
        #expect(weakOwner == nil)
        #expect(
            cache.value(for: 1) {
                -1
            } == 42
        )
    }

    @Test
    func failuresDoNotInsertOrEvict() {
        var cache = MemoizationCache<Int, Int>(capacity: 2)
        _ = cache.value(for: 1) {
            10
        }
        _ = cache.value(for: 2) {
            20
        }
        #expect(throws: CalculationError.failed) {
            try cache.value(for: 3) {
                throw CalculationError.failed
            }
        }
        #expect(cache.count == 2)
        _ = cache.value(for: 3) {
            30
        }
        #expect(
            cache.value(for: 2) {
                -1
            } == 20
        )
        #expect(
            cache.value(for: 1) {
                100
            } == 100
        )
    }

    @Test
    func hitDoesNotInvokeThrowingClosure() {
        var cache = MemoizationCache<Int, Int>(capacity: 1)
        _ = cache.value(for: 1) {
            10
        }
        #expect(throws: Never.self) {
            let result = try cache.value(for: 1) {
                throw CalculationError.failed
            }
            #expect(result == 10)
        }
    }

    @Test
    func hitsPromoteAndInsertionsEvictOldest() {
        var cache = MemoizationCache<Int, Int>(capacity: 3)
        for key in 1 ... 3 {
            _ = cache.value(for: key) {
                key * 10
            }
        }

        #expect(
            cache.value(for: 1) {
                -1
            } == 10
        )
        _ = cache.value(for: 4) {
            40
        }
        #expect(
            cache.value(for: 3) {
                -1
            } == 30
        )
        #expect(
            cache.value(for: 1) {
                -1
            } == 10
        )
        #expect(
            cache.value(for: 2) {
                200
            } == 200
        )
        #expect(cache.count == 3)
    }

    @Test
    func nilIsAStoredValue() {
        var cache = MemoizationCache<Int, Int?>(capacity: 1)
        var computations = 0
        let first = cache.value(for: 1) {
            computations += 1
            return nil
        }
        let second = cache.value(for: 1) {
            computations += 1
            return 42
        }
        #expect(first == nil)
        #expect(second == nil)
        #expect(computations == 1)
        #expect(cache.count == 1)
    }

    @Test(arguments: [1, 2, 3])
    func removesHeadMiddleAndTail(keyToRemove: Int) {
        var cache = MemoizationCache<Int, Int>(capacity: 3)
        for key in 1 ... 3 {
            _ = cache.value(for: key) {
                key * 10
            }
        }

        cache.removeValue(for: keyToRemove)
        cache.removeValue(for: 99)
        #expect(cache.count == 2)
        _ = cache.value(for: 4) {
            40
        }
        #expect(cache.count == 3)
        for key in 1 ... 3 where key != keyToRemove {
            #expect(
                cache.value(for: key) {
                    -1
                } == key * 10
            )
        }

        #expect(
            cache.value(for: keyToRemove) {
                100
            } == 100
        )
        #expect(cache.count == 3)
    }

    @Test
    func removesSingleEntryAndClears() {
        var cache = MemoizationCache<Int, Int>(capacity: 1)
        _ = cache.value(for: 1) {
            10
        }
        cache.removeValue(for: 1)
        #expect(cache.count == 0)
        _ = cache.value(for: 2) {
            20
        }
        #expect(
            cache.value(for: 2) {
                -1
            } == 20
        )
        cache.removeAll()
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.capacity == 1)
        #expect(
            cache.value(for: 2) {
                200
            } == 200
        )
    }

    @Test
    func retainsEntriesButReleasesEvictedRemovedAndClearedObjects() {
        var cache = MemoizationCache<ObjectKey, ObjectKey>(capacity: 1)
        var key: ObjectKey? = ObjectKey()
        var value: ObjectKey? = ObjectKey()
        weak let weakKey = key
        weak let weakValue = value
        if let key, let value {
            _ = cache.value(for: key) {
                value
            }
        }

        key = nil
        value = nil
        #expect(weakKey != nil)
        #expect(weakValue != nil)
        let replacementKey = ObjectKey()
        _ = cache.value(for: replacementKey) {
            ObjectKey()
        }
        #expect(weakKey == nil)
        #expect(weakValue == nil)

        var removedValue: ObjectKey? = cache.value(for: replacementKey) {
            ObjectKey()
        }
        weak let weakRemovedValue = removedValue
        removedValue = nil
        cache.removeValue(for: replacementKey)
        #expect(weakRemovedValue == nil)

        var clearedValue: ObjectKey? = ObjectKey()
        weak let weakClearedValue = clearedValue
        if let clearedValue {
            _ = cache.value(for: replacementKey) {
                clearedValue
            }
        }

        clearedValue = nil
        cache.removeAll()
        #expect(weakClearedValue == nil)
    }

    @Test
    func transitionsMatchSimpleLRUModel() {
        var cache = MemoizationCache<Int, Int>(capacity: 4)
        var oldestToNewest: [Int] = []
        var values: [Int: Int] = [:]
        for step in 0 ..< 500 {
            let key = (step * 17 + step / 7) % 9
            if step.isMultiple(of: 31) {
                cache.removeAll()
                oldestToNewest.removeAll()
                values.removeAll()
            } else if step.isMultiple(of: 5) {
                cache.removeValue(for: key)
                oldestToNewest.removeAll {
                    $0 == key
                }
                values.removeValue(forKey: key)
            } else {
                let expected = values[key] ?? step
                if values[key] == nil, oldestToNewest.count == 4 {
                    values.removeValue(forKey: oldestToNewest.removeFirst())
                }

                values[key] = expected
                oldestToNewest.removeAll {
                    $0 == key
                }
                oldestToNewest.append(key)
                #expect(
                    cache.value(for: key) {
                        step
                    } == expected
                )
            }

            #expect(cache.count == values.count)
        }
    }

    @Test
    func zeroCapacityAlwaysComputes() {
        var cache = MemoizationCache<Int, Int>(capacity: 0)
        var computations = 0
        for expected in 1 ... 3 {
            #expect(
                cache.value(for: 1) {
                    computations += 1
                    return computations
                } == expected
            )
            #expect(cache.count == 0)
        }
    }
}

extension MemoizationCacheTests {
    private enum CalculationError: Error, Equatable {
        case failed
    }
}

extension MemoizationCacheTests {
    private struct CollidingKey: Hashable {
        let value: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(0)
        }
    }
}

extension MemoizationCacheTests {
    private final class ObjectKey: Hashable {
        static func == (lhs: ObjectKey, rhs: ObjectKey) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}
