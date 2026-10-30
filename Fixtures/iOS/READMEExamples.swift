// Complete README sizing, composition, ownership, and mapped-root examples.
import DerivedKeysUI
import DerivedKeysUIExample
import UIKit

@MainActor
func readmeMeasurements(view: DocumentContentView, availableSize: CGSize) {
    let textSizes = SizeCache<UITextView>(
        dependingOn: \.text,
        \.font,
        \.textContainer.maximumNumberOfLines,
        capacity: 256
    )

    let size = textSizes.size(of: view.textView, toFit: availableSize)

    let buttonSizes = SizeCache<UIButton>(
        dependingOn: \.currentTitle,
        \.titleLabel?.font,
        capacity: 256
    )
    let text = textSizes.bound(to: \DocumentContentView.textView)
    let button = buttonSizes.bound(to: \DocumentContentView.button)

    let contentSizes = SizeCache<DocumentContentView>(
        dependingOn: \.padding,
        \.spacing,
        \.showsButton,
        children: text,
        button,
        capacity: 256
    ) { view, proposal in
        let innerProposal = CGSize(
            width: max(0, proposal.width - 2 * view.padding),
            height: CGFloat.greatestFiniteMagnitude
        )
        let textSize = text.size(of: view, toFit: innerProposal)
        let buttonSize =
            view.showsButton
            ? button.size(of: view, toFit: innerProposal)
            : .zero
        return CGSize(
            width: proposal.width,
            height: 2 * view.padding + textSize.height + buttonSize.height
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
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 128)
}

@MainActor
final class PairView: UIView {
    let title = UILabel()
    let subtitle = UILabel()
}

@MainActor
func makePairSizes(titles: SizeCache<UILabel>) -> SizeCache<PairView> {
    let title = titles.bound(to: \PairView.title)
    let subtitle = titles.bound(to: \PairView.subtitle)
    return SizeCache<PairView>(
        children: title,
        subtitle,
        capacity: 128
    ) { view, proposal in
        let titleSize = title.size(of: view, toFit: proposal)
        let subtitleSize = subtitle.size(of: view, toFit: proposal)
        return CGSize(
            width: max(titleSize.width, subtitleSize.width),
            height: titleSize.height + subtitleSize.height
        )
    }
}
