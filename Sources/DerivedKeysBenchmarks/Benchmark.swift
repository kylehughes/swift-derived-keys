import DerivedKeys
import Dispatch
import Foundation

@main
struct DerivedKeysBenchmarks {
    private typealias Dependencies = DerivedKey<KeyPair<OriginalKey<[UInt8]>, OriginalKey<Int>>>
    private typealias Projection = KeyProjection<Operation, Input, Dependencies>
    private typealias TypedKey = RequestKey<Operation, Dependencies, Int>

    @MainActor
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        if options.scenario.rawValue.hasPrefix("size-") {
            try SizeBenchmarks.run(
                scenario: options.scenario.rawValue,
                iterations: options.iterations,
                payloadBytes: options.payloadBytes,
                capacity: options.capacity
            )
            return
        }
        let payloadSize = options.scenario == .largePayload ? max(options.payloadBytes, 262_144) : options.payloadBytes
        let payload = (0 ..< payloadSize)
            .map {
                UInt8(truncatingIfNeeded: $0 &* 31 &+ 7)
            }
        let projection = KeyProjection(operation: Operation.self) { (input: Input) in
            DerivedKey(
                "document",
                children: KeyPair(
                    OriginalKey("content", value: input.payload),
                    OriginalKey("format", value: input.variant)
                )
            )
        }
        let measurements: [Measurement]
        switch options.scenario {
        case .typedProjection:
            measurements = [measureProjection(options: options, payload: payload, projection: projection)]
        case .typedHash:
            measurements = [measureHash(options: options, payload: payload, projection: projection)]
        case .sharedSource:
            measurements = try measureSharedSource(options: options, payload: payload)
        default:
            measurements = [measureCalculation(options: options, payload: payload, projection: projection)]
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for measurement in measurements {
            let data = try encoder.encode(measurement)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }

    @inline(never)
    private static func calculate(_ input: Input) -> UInt64 {
        var result = UInt64(truncatingIfNeeded: input.variant) &+ 14_695_981_039_346_656_037
        for round in 0 ..< 4 {
            for byte in input.payload {
                result = (result ^ UInt64(byte)) &* 1_099_511_628_211
            }
            result ^= UInt64(round)
        }

        return result
    }

    private static func hashChecksum<Key>(_ keys: [Key]) -> UInt64 where Key: Hashable {
        keys.reduce(0) {
            $0 &+ UInt64(truncatingIfNeeded: $1.hashValue)
        }
    }

    private static func measureCalculation(
        options: Options,
        payload: [UInt8],
        projection: Projection
    ) -> Measurement {
        let capacity: Int
        switch options.scenario {
        case .coldMiss:
            capacity = options.iterations
        case .direct:
            capacity = 0
        default:
            capacity = options.capacity
        }
        let workingSet = options.scenario == .eviction ? capacity + 1 : min(options.capacity, 64)
        var cache = MemoizationCache<TypedKey, UInt64>(capacity: capacity)
        var checksum: UInt64 = 0
        var computations = 0
        var warmupComputations = 0
        if [.warmHit, .irrelevantChange, .largePayload].contains(options.scenario) {
            let warmupCount = options.scenario == .warmHit ? workingSet : 1
            for variant in 0 ..< warmupCount {
                let input = Input(payload: payload, variant: variant, irrelevant: 0)
                _ = cache.value(for: projection.key(for: input, context: 0)) {
                    warmupComputations += 1
                    return calculate(input)
                }
            }
        }

        let start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            let variant: Int
            switch options.scenario {
            case .coldMiss, .relevantChange:
                variant = iteration
            case .direct, .warmHit, .eviction:
                variant = iteration % workingSet
            default:
                variant = 0
            }
            let input = Input(payload: payload, variant: variant, irrelevant: iteration)
            let result: UInt64
            if options.scenario == .direct {
                computations += 1
                result = calculate(input)
            } else {
                result = cache.value(for: projection.key(for: input, context: 0)) {
                    computations += 1
                    return calculate(input)
                }
            }

            checksum &+= result
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let expectedComputations =
            [.warmHit, .irrelevantChange, .largePayload].contains(options.scenario)
            ? 0 : options.iterations
        precondition(computations == expectedComputations, "Unexpected cache hit or miss count.")

        return Measurement(
            options: options,
            phase: options.scenario == .direct ? "computation" : "projection+cache+computation-on-miss",
            elapsed: elapsed,
            checksum: checksum,
            computations: computations,
            warmupComputations: warmupComputations,
            capacity: capacity,
            entries: cache.count,
            payloadBytes: payload.count
        )
    }

    private static func measureHash(options: Options, payload: [UInt8], projection: Projection) -> Measurement {
        let keys = (0 ..< 64)
            .map {
                projection.key(for: Input(payload: payload, variant: $0, irrelevant: 0), context: 0)
            }
        var checksum: UInt64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            checksum &+= UInt64(truncatingIfNeeded: keys[iteration % keys.count].hashValue)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start

        return Measurement(
            options: options,
            phase: "hash-preconstructed-key",
            elapsed: elapsed,
            checksum: checksum,
            payloadBytes: payload.count
        )
    }

    private static func measureProjection(options: Options, payload: [UInt8], projection: Projection) -> Measurement {
        let first = projection.key(for: Input(payload: payload, variant: 0, irrelevant: 0), context: 0)
        var observedKeys = Array(repeating: first, count: 64)
        let start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            observedKeys[iteration % observedKeys.count] = project(
                Input(payload: payload, variant: iteration, irrelevant: iteration),
                using: projection
            )
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start

        return Measurement(
            options: options,
            phase: "projection+64-slot-observation",
            elapsed: elapsed,
            checksum: hashChecksum(observedKeys),
            payloadBytes: payload.count
        )
    }

    private static func measureSharedSource(options: Options, payload: [UInt8]) throws -> [Measurement] {
        let content = KeySource<Input>("content", provider: \.payload)
        let format = KeySource<Input>("format", provider: \.variant)
        let left = try KeySource("left", children: [content, format])
        let right = try KeySource("right", children: [content])
        let source = try KeySource("document", children: [left, right])
        let input = Input(payload: payload, variant: 0, irrelevant: 0)
        let first = source.snapshot(for: input)
        var snapshots = Array(repeating: first, count: 64)
        var measurements: [Measurement] = []
        var start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            snapshots[iteration % snapshots.count] = source.snapshot(
                for: Input(payload: payload, variant: iteration, irrelevant: iteration)
            )
        }
        var elapsed = DispatchTime.now().uptimeNanoseconds - start
        measurements.append(
            Measurement(
                options: options,
                phase: "snapshot+64-slot-observation",
                elapsed: elapsed,
                checksum: hashChecksum(snapshots),
                payloadBytes: payload.count
            )
        )

        var checksum: UInt64 = 0
        start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            checksum &+= UInt64(truncatingIfNeeded: snapshots[iteration % snapshots.count].hashValue)
        }
        elapsed = DispatchTime.now().uptimeNanoseconds - start
        measurements.append(
            Measurement(
                options: options,
                phase: "hash-preconstructed-snapshot",
                elapsed: elapsed,
                checksum: checksum,
                payloadBytes: payload.count
            )
        )

        var cache = MemoizationCache<DependencySnapshot, UInt64>(capacity: options.capacity)
        _ = cache.value(for: first) {
            calculate(input)
        }
        var computations = 0
        checksum = 0
        start = DispatchTime.now().uptimeNanoseconds
        for iteration in 0 ..< options.iterations {
            let captured = Input(payload: payload, variant: 0, irrelevant: iteration)
            checksum &+= cache.value(for: source.snapshot(for: captured)) {
                computations += 1
                return calculate(captured)
            }
        }
        elapsed = DispatchTime.now().uptimeNanoseconds - start
        measurements.append(
            Measurement(
                options: options,
                phase: "snapshot+cache+computation-on-miss",
                elapsed: elapsed,
                checksum: checksum,
                computations: computations,
                warmupComputations: 1,
                capacity: options.capacity,
                entries: cache.count,
                payloadBytes: payload.count
            )
        )

        return measurements
    }

    @inline(never)
    private static func project(_ input: Input, using projection: Projection) -> TypedKey {
        projection.key(for: input, context: 0)
    }
}

extension DerivedKeysBenchmarks {
    private enum ArgumentError: Error, CustomStringConvertible {
        case invalid(String)

        var description: String {
            switch self {
            case .invalid(let message):
                message
            }
        }
    }
}

extension DerivedKeysBenchmarks {
    private struct Input {
        let payload: [UInt8]
        let variant: Int
        let irrelevant: Int
    }
}

extension DerivedKeysBenchmarks {
    private struct Measurement: Encodable {
        let allocationCount: Int? = nil
        let allocationMeasurement = "unknown; no allocation profiler attached"
        let cacheCapacity: Int
        let checksum: String
        let computationCount: Int
        let elapsedNanoseconds: UInt64
        let entryCount: Int
        let iterations: Int
        let logicalPayloadBytesAcrossEntries: Int
        let nanosecondsPerOperation: Double
        let payloadBytes: Int
        let phase: String
        let retainedMemoryAccounting = "payload references and UInt64 result bytes only; storage overhead unknown"
        let requestedCapacity: Int
        let resultValueBytesAcrossEntries: Int
        let scenario: String
        let uniquePayloadBytesReferencedByEntries: Int
        let warmupComputationCount: Int

        init(
            options: Options,
            phase: String,
            elapsed: UInt64,
            checksum: UInt64,
            computations: Int = 0,
            warmupComputations: Int = 0,
            capacity: Int = 0,
            entries: Int = 0,
            payloadBytes: Int
        ) {
            cacheCapacity = capacity
            self.checksum = String(checksum)
            computationCount = computations
            elapsedNanoseconds = elapsed
            entryCount = entries
            iterations = options.iterations
            logicalPayloadBytesAcrossEntries = entries * payloadBytes
            nanosecondsPerOperation = Double(elapsed) / Double(options.iterations)
            self.payloadBytes = payloadBytes
            self.phase = phase
            requestedCapacity = options.capacity
            resultValueBytesAcrossEntries = entries * MemoryLayout<UInt64>.stride
            scenario = options.scenario.rawValue
            uniquePayloadBytesReferencedByEntries = entries > 0 ? payloadBytes : 0
            warmupComputationCount = warmupComputations
        }
    }
}

extension DerivedKeysBenchmarks {
    private enum Operation {}
}

extension DerivedKeysBenchmarks {
    private struct Options {
        var capacity = 128
        var iterations = 1_000
        var payloadBytes = 4_096
        var scenario = Scenario.warmHit

        init(arguments: [String]) throws {
            guard arguments.count.isMultiple(of: 2) else {
                throw ArgumentError.invalid("Expected --case NAME, --iterations N, --payload-bytes N, or --capacity N.")
            }

            for offset in stride(from: 0, to: arguments.count, by: 2) {
                let flag = arguments[offset]
                let value = arguments[offset + 1]
                switch flag {
                case "--case":
                    guard let scenario = Scenario(rawValue: value) else {
                        throw ArgumentError.invalid("Unknown case: \(value).")
                    }

                    self.scenario = scenario
                case "--iterations":
                    iterations = try Self.positiveInteger(value, maximum: 1_000_000)
                case "--payload-bytes":
                    payloadBytes = try Self.positiveInteger(value, maximum: 16_777_216)
                case "--capacity":
                    capacity = try Self.positiveInteger(value, maximum: 1_000_000)
                default:
                    throw ArgumentError.invalid("Unknown option: \(flag).")
                }
            }
        }

        private static func positiveInteger(_ value: String, maximum: Int) throws -> Int {
            guard let number = Int(value), (1 ... maximum).contains(number) else {
                throw ArgumentError.invalid("Expected an integer in 1...\(maximum), got \(value).")
            }

            return number
        }
    }
}

extension DerivedKeysBenchmarks {
    private enum Scenario: String {
        case sizeSnapshot = "size-snapshot"
        case sizeWarmParent = "size-warm-parent"
        case sizeParentMiss = "size-parent-miss"
        case sizeCold = "size-cold"
        case sizeDirect = "size-direct"
        case typedProjection = "typed-projection"
        case typedHash = "typed-hash"
        case direct
        case coldMiss = "cold-miss"
        case warmHit = "warm-hit"
        case relevantChange = "relevant-change"
        case irrelevantChange = "irrelevant-change"
        case largePayload = "large-payload"
        case sharedSource = "shared-source"
        case eviction
    }
}
