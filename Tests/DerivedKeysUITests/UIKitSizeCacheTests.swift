#if canImport(UIKit)
import CoreGraphics
import DerivedKeysUI
import Testing
import UIKit

@MainActor
struct UIKitSizeCacheTests {
    @Test func nestedMainActorUIKitPathsAndMappedHeterogeneousChildren() {
        let text = SizeCache<UILabel>(dependingOn: \.text, \.numberOfLines, capacity: 2) { label, proposal in
            label.sizeThatFits(proposal)
        }
        let button = SizeCache<UIButton>(dependingOn: \.isEnabled, \.titleLabel?.text, capacity: 2) {
            button,
            proposal in
            button.sizeThatFits(proposal)
        }
        let parent = SizeCache<Content>(
            dependingOn: \.label.text,
            \.button.isEnabled,
            children: text.at(\.label),
            button.at(\.button),
            capacity: 2
        ) { root, proposal in
            let textSize = text.size(of: root.label, toFit: proposal)
            let buttonSize = button.size(of: root.button, toFit: proposal)
            return CGSize(width: max(textSize.width, buttonSize.width), height: textSize.height + buttonSize.height)
        }
        let root = Content()
        root.label.text = "Example"
        root.button.setTitle("Continue", for: .normal)
        let snapshot = parent.snapshot(of: root)
        let result = parent.size(of: root, toFit: CGSize(width: 200, height: 100))
        #expect(result.height > 0)
        #expect(parent.count == 1)
        root.label.text = "Changed"
        #expect(snapshot != parent.snapshot(of: root))
    }
}

extension UIKitSizeCacheTests {
    @MainActor
    private final class Content {
        let label = UILabel()
        let button = UIButton(type: .system)
    }
}
#endif
