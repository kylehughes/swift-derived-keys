// Complete README sizing, composition, ownership, and mapped-root examples.
import DerivedKeysUI
import DerivedKeysUIExample
import UIKit

@MainActor
func readmeMeasurements(view: DocumentContentView, availableSize: CGSize) {
    let textSizes = SizeCache<DocumentContentView>(
        dependingOn: \.content,
        \.isExpanded,
        \.traitCollection.preferredContentSizeCategory,
        capacity: 256
    ) { view, proposal in
        view.textView.sizeThatFits(proposal)
    }

    let size = textSizes.size(of: view, toFit: availableSize)

    let buttonSizes = SizeCache<DocumentContentView>(
        dependingOn: \.traitCollection.preferredContentSizeCategory,
        capacity: 256
    ) { view, proposal in
        view.button.sizeThatFits(proposal)
    }

    let contentSizes = SizeCache<DocumentContentView>(
        dependingOn: \.padding,
        \.spacing,
        \.showsButton,
        children: textSizes,
        buttonSizes,
        capacity: 256
    ) { view, proposal in
        let innerProposal = CGSize(
            width: max(0, proposal.width - 2 * view.padding),
            height: CGFloat.greatestFiniteMagnitude
        )
        let text = textSizes.size(of: view, toFit: innerProposal)
        let button =
            view.showsButton
            ? buttonSizes.size(of: view, toFit: innerProposal)
            : .zero
        return CGSize(
            width: proposal.width,
            height: 2 * view.padding + text.height + button.height
                + (view.showsButton ? view.spacing : 0)
        )
    }

    let initial = contentSizes.size(of: view, toFit: availableSize)
    view.spacing += 4
    let spaced = contentSizes.size(of: view, toFit: availableSize)  // Parent miss; children hit.
    view.content += " Another paragraph."
    let edited = contentSizes.size(of: view, toFit: availableSize)  // Parent and text miss; button hits.

    let outerSizes = SizeCache<DocumentContentView>(
        children: contentSizes,
        capacity: 256
    ) { view, proposal in
        contentSizes.size(of: view, toFit: proposal)
    }

    _ = (size, initial, spaced, edited, outerSizes)
}

@MainActor
final class DocumentScreen: UIViewController {
    let sizeCaches = DocumentSizeCaches()
    private lazy var contentView = DocumentContentView(caches: sizeCaches)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(contentView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let available = view.bounds.inset(by: view.safeAreaInsets)
        let size = contentView.sizeThatFits(
            CGSize(
                width: max(0, available.width),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        contentView.frame = CGRect(origin: available.origin, size: size)
    }
}

@MainActor
func makeTitleSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 128) { label, proposal in
        label.sizeThatFits(proposal)
    }
}

@MainActor
final class PairView: UIView {
    let title = UILabel()
    let subtitle = UILabel()
}

@MainActor
func makePairSizes(titles: SizeCache<UILabel>) -> SizeCache<PairView> {
    SizeCache<PairView>(
        children: titles.at(\.title),
        titles.at(\.subtitle),
        capacity: 128
    ) { view, proposal in
        let title = titles.size(of: view.title, toFit: proposal)
        let subtitle = titles.size(of: view.subtitle, toFit: proposal)
        return CGSize(width: max(title.width, subtitle.width), height: title.height + subtitle.height)
    }
}
