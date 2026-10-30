import DerivedKeysUI
import UIKit

@MainActor
final class UIKitBindingRoot {
    let label = UILabel()
    let button = UIButton(type: .system)
}

@MainActor
final class UIKitBindingEnvelope {
    let root = UIKitBindingRoot()
}

@MainActor
func validDefaultFittingAndBinding() {
    let label = SizeCache<UILabel>(dependingOn: \.text, \.numberOfLines, \.traitCollection.preferredContentSizeCategory, capacity: 2)
    let button = SizeCache<UIButton>(dependingOn: \.titleLabel?.text, \.isEnabled, capacity: 2)
    let empty = SizeCache<UIView>(capacity: 0)
    let text = label.bound(to: \UIKitBindingRoot.label)
    let action = button.bound(to: \UIKitBindingRoot.button)
    let parent = SizeCache<UIKitBindingRoot>(children: text, action, capacity: 2) { root, proposal in
        let textSize = text.size(of: root, toFit: proposal)
        let actionSize = action.size(of: root, toFit: proposal)
        return CGSize(width: max(textSize.width, actionSize.width), height: textSize.height + actionSize.height)
    }
    let root = UIKitBindingRoot()
    _ = parent.size(of: root, toFit: .zero)
    _ = text.bound(to: \UIKitBindingEnvelope.root).size(of: UIKitBindingEnvelope(), toFit: .zero)
    _ = text.at(\UIKitBindingEnvelope.root).snapshot(of: UIKitBindingEnvelope())
    _ = label.bound(to: \UILabel.self).size(of: root.label, toFit: .zero)
    _ = empty.size(of: UIView(), toFit: .zero)
}
