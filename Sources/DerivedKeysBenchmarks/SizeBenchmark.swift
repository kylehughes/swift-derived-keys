import CoreGraphics
import DerivedKeys
import DerivedKeysUI
import Dispatch
import Foundation

@MainActor
enum SizeBenchmarks {
    static func run(scenario: String, iterations: Int, payloadBytes: Int, capacity: Int) throws {
        let payload = (0 ..< payloadBytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let counts = Counts()
        let left = SizeCache<SizeBenchmarkChild>(dependingOn: \.payload, \.variant, \.scale, capacity: capacity) {
            input,
            proposal in
            counts.left += 1
            return calculate(input, proposal: proposal)
        }
        let right = SizeCache<SizeBenchmarkChild>(dependingOn: \.payload, \.variant, \.scale, capacity: capacity) {
            input,
            proposal in
            counts.right += 1
            return calculate(input, proposal: proposal)
        }
        let parent = SizeCache<SizeBenchmarkRoot>(
            dependingOn: \.spacing,
            \.horizontal,
            children: left.at(\.left),
            right.at(\.right),
            capacity: capacity
        ) { input, proposal in
            counts.parent += 1
            return compose(
                input,
                left: left.size(of: input.left, toFit: proposal),
                right: right.size(of: input.right, toFit: proposal)
            )
        }
        let proposal = CGSize(width: 320, height: 240)
        let initial = input(scenario: scenario, iteration: 0, payload: payload)
        if scenario == "size-warm-parent" {
            _ = parent.size(of: initial, toFit: proposal)
        } else if scenario == "size-parent-miss" {
            _ = left.size(of: initial.left, toFit: proposal)
            _ = right.size(of: initial.right, toFit: proposal)
        }
        let warmup = counts.snapshot
        var checksum: UInt64 = 0
        let elapsed: UInt64
        let phase: String
        if scenario == "size-snapshot" {
            var snapshots = Array(repeating: parent.snapshot(of: initial), count: 64)
            let start = DispatchTime.now().uptimeNanoseconds
            for iteration in 0 ..< iterations {
                snapshots[iteration % snapshots.count] = parent.snapshot(
                    of: input(scenario: scenario, iteration: iteration, payload: payload)
                )
            }
            elapsed = DispatchTime.now().uptimeNanoseconds - start
            checksum = snapshots.reduce(0) { $0 &+ UInt64(truncatingIfNeeded: $1.hashValue) }
            phase = "snapshot+64-slot-observation"
        } else {
            let start = DispatchTime.now().uptimeNanoseconds
            for iteration in 0 ..< iterations {
                let root = input(scenario: scenario, iteration: iteration, payload: payload)
                let size: CGSize
                if scenario == "size-direct" {
                    counts.parent += 1
                    counts.left += 1
                    counts.right += 1
                    size = direct(root, proposal: proposal)
                } else {
                    size = parent.size(of: root, toFit: proposal)
                }
                checksum &+= sizeChecksum(size)
            }
            elapsed = DispatchTime.now().uptimeNanoseconds - start
            phase = scenario == "size-direct" ? "direct-child+parent-calculation" : "snapshot+cache+measurement-on-miss"
            var expectedChecksum: UInt64 = 0
            for iteration in 0 ..< iterations {
                expectedChecksum &+= sizeChecksum(
                    direct(input(scenario: scenario, iteration: iteration, payload: payload), proposal: proposal)
                )
            }
            precondition(checksum == expectedChecksum, "Size benchmark differs from direct calculation.")
        }
        let measured = counts.snapshot - warmup
        let expected: CountSnapshot
        switch scenario {
        case "size-snapshot", "size-warm-parent": expected = CountSnapshot(parent: 0, left: 0, right: 0)
        case "size-parent-miss": expected = CountSnapshot(parent: iterations, left: 0, right: 0)
        default: expected = CountSnapshot(parent: iterations, left: iterations, right: iterations)
        }
        precondition(measured == expected, "Unexpected parent or child measurement count.")
        let observations = [
            CacheObservation(
                name: "parent",
                cacheCapacity: parent.capacity,
                entryCount: parent.count,
                computationCount: measured.parent,
                warmupComputationCount: warmup.parent
            ),
            CacheObservation(
                name: "left",
                cacheCapacity: left.capacity,
                entryCount: left.count,
                computationCount: measured.left,
                warmupComputationCount: warmup.left
            ),
            CacheObservation(
                name: "right",
                cacheCapacity: right.capacity,
                entryCount: right.count,
                computationCount: measured.right,
                warmupComputationCount: warmup.right
            ),
        ]
        let measurement = Measurement(
            caches: observations,
            checksum: String(checksum),
            elapsedNanoseconds: elapsed,
            iterations: iterations,
            nanosecondsPerOperation: Double(elapsed) / Double(iterations),
            payloadBytesPerChild: payloadBytes,
            phase: phase,
            requestedCapacityPerCache: capacity,
            scenario: scenario,
            storedResultValueBytesAcrossCaches: observations.reduce(0) {
                $0 + $1.entryCount * MemoryLayout<CGSize>.stride
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(measurement))
        FileHandle.standardOutput.write(Data([10]))
    }

    @inline(never)
    private static func calculate(_ input: SizeBenchmarkChild, proposal: CGSize) -> CGSize {
        var result = UInt64(truncatingIfNeeded: input.variant) &+ 14_695_981_039_346_656_037
        for round in 0 ..< 4 {
            for byte in input.payload {
                result = (result ^ UInt64(byte)) &* 1_099_511_628_211
            }
            result ^= UInt64(round)
        }
        return CGSize(
            width: min(proposal.width, CGFloat(result % 257 + 1) * input.scale),
            height: min(proposal.height, CGFloat((result >> 8) % 127 + 1) * input.scale)
        )
    }

    private static func compose(_ input: SizeBenchmarkRoot, left: CGSize, right: CGSize) -> CGSize {
        if input.horizontal {
            return CGSize(
                width: left.width + right.width + CGFloat(input.spacing),
                height: max(left.height, right.height)
            )
        }
        return CGSize(width: max(left.width, right.width), height: left.height + right.height + CGFloat(input.spacing))
    }

    private static func direct(_ input: SizeBenchmarkRoot, proposal: CGSize) -> CGSize {
        compose(
            input,
            left: calculate(input.left, proposal: proposal),
            right: calculate(input.right, proposal: proposal)
        )
    }

    private static func input(scenario: String, iteration: Int, payload: [UInt8]) -> SizeBenchmarkRoot {
        let changingChildren = ["size-snapshot", "size-cold", "size-direct"].contains(scenario)
        let variant = changingChildren ? iteration * 2 : 0
        return SizeBenchmarkRoot(
            left: SizeBenchmarkChild(payload: payload, variant: variant, scale: 1),
            right: SizeBenchmarkChild(payload: payload, variant: variant + 1, scale: 2),
            spacing: scenario == "size-parent-miss" ? iteration + 1 : 1,
            horizontal: true
        )
    }

    private static func sizeChecksum(_ size: CGSize) -> UInt64 {
        UInt64(size.width) &* 65_537 &+ UInt64(size.height)
    }
}

extension SizeBenchmarks {
    private struct CacheObservation: Encodable {
        let name: String
        let cacheCapacity: Int
        let entryCount: Int
        let computationCount: Int
        let warmupComputationCount: Int
    }

    private struct CountSnapshot: Equatable {
        let parent: Int
        let left: Int
        let right: Int

        static func - (lhs: Self, rhs: Self) -> Self {
            Self(parent: lhs.parent - rhs.parent, left: lhs.left - rhs.left, right: lhs.right - rhs.right)
        }
    }

    private final class Counts {
        var parent = 0
        var left = 0
        var right = 0

        var snapshot: CountSnapshot { CountSnapshot(parent: parent, left: left, right: right) }
    }

    private struct Measurement: Encodable {
        let allocationCount: Int? = nil
        let allocationMeasurement = "unknown; no allocation profiler attached"
        let caches: [CacheObservation]
        let checksum: String
        let elapsedNanoseconds: UInt64
        let iterations: Int
        let nanosecondsPerOperation: Double
        let payloadBytesPerChild: Int
        let phase: String
        let requestedCapacityPerCache: Int
        let retainedMemoryAccounting =
            "stored CGSize result bytes only; total retained key bytes and storage overhead unknown"
        let scenario: String
        let storedResultValueBytesAcrossCaches: Int
    }
}

struct SizeBenchmarkChild {
    let payload: [UInt8]
    let variant: Int
    let scale: CGFloat
}

struct SizeBenchmarkRoot {
    let left: SizeBenchmarkChild
    let right: SizeBenchmarkChild
    let spacing: Int
    let horizontal: Bool
}
