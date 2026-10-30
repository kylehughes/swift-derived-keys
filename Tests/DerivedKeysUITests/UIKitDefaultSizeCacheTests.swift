#if canImport(UIKit)
import DerivedKeysUI
import Testing
import UIKit

@MainActor
struct UIKitDefaultSizeCacheTests {
    @Test func fittingReceivesSuppliedViewAndNormalizedExactProposal() {
        let cache = SizeCache<ProbeView>(dependingOn: \.content.text, \.enabled, capacity: 8)
        let first = ProbeView()
        let second = ProbeView()
        for proposal in [
            CGSize(width: -CGFloat.zero, height: -CGFloat.zero),
            CGSize(width: 1, height: 2),
            CGSize(width: CGFloat(1).nextUp, height: 2),
            CGSize(width: 1, height: CGFloat(2).nextUp),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        ] {
            #expect(cache.size(of: first, toFit: proposal) == proposal)
            #expect(cache.size(of: second, toFit: proposal) == proposal)
        }
        #expect(first.received.count == 5)
        #expect(second.received.isEmpty)
        #expect(first.received[0].width.native.bitPattern == CGFloat.zero.native.bitPattern)
        #expect(first.received[0].height.native.bitPattern == CGFloat.zero.native.bitPattern)
        second.ignored += 1
        _ = cache.size(of: second, toFit: .zero)
        #expect(second.received.isEmpty)
        second.content.text = "changed"
        _ = cache.size(of: second, toFit: .zero)
        #expect(second.received == [.zero])
        second.enabled = false
        _ = cache.size(of: second, toFit: .zero)
        #expect(second.received.count == 2)
    }

    @Test func zeroPathFittingSharesResultsAcrossInstancesAndBindings() {
        let cache = SizeCache<ProbeView>(capacity: 1)
        let first = ProbeView()
        let second = ProbeView()
        let bound = cache.bound(to: \ProbeView.self)
        #expect(bound.size(of: first, toFit: .zero) == .zero)
        #expect(cache.size(of: second, toFit: .zero) == .zero)
        #expect(first.received.count == 1)
        #expect(second.received.isEmpty)
        #expect(cache.count == 1)
    }
}

extension UIKitDefaultSizeCacheTests {
    @MainActor
    private final class ProbeView: UIView {
        struct Content {
            var text = "text"
        }
        var content = Content()
        var enabled = true
        var ignored = 0
        var received: [CGSize] = []

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            received.append(size)
            return size
        }
    }
}
#endif
