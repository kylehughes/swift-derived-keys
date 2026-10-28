import DerivedKeysUI
import UIKit

final class UIKitSizeRoot {
    let label: UILabel
    let button: UIButton
    var revision = 0

    @MainActor
    init() {
        label = UILabel()
        button = UIButton(type: .system)
    }
}

@MainActor
func validUIKitSizeAccess() {
    let label = SizeCache<UILabel>(
        dependingOn: \.text,
        \.font,
        \.numberOfLines,
        \.traitCollection.preferredContentSizeCategory,
        capacity: 8
    ) { view, proposal in view.sizeThatFits(proposal) }
    let button = SizeCache<UIButton>(
        dependingOn: \.isEnabled,
        \.titleLabel?.text,
        \.traitCollection.layoutDirection,
        capacity: 8
    ) { view, proposal in view.sizeThatFits(proposal) }
    let sameRoot = SizeCache<UIKitSizeRoot>(dependingOn: \.revision, capacity: 8) { _, size in size }
    let root = UIKitSizeRoot()
    let mapped = SizeCache<UIKitSizeRoot>(children: label.at(\.label), button.at(\.button), capacity: 8) {
        root,
        proposal in label.size(of: root.label, toFit: proposal)
    }
    let mixed = SizeCache<UIKitSizeRoot>(
        dependingOn: \.label.text,
        \.button.isHidden,
        children: sameRoot,
        label.at(\.label),
        button.at(\.button),
        capacity: 8
    ) { root, proposal in mapped.size(of: root, toFit: proposal) }
    let empty = SizeCache<UIKitSizeRoot>(capacity: 0) { _, proposal in proposal }
    _ = mixed.snapshot(of: root)
    _ = mixed.size(of: root, toFit: CGSize(width: 100, height: 20))
    _ = empty.size(of: root, toFit: .zero)
    mixed.removeSize(of: root, toFit: .zero)
    mixed.removeAll()
}
