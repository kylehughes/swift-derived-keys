// Complete README sizing, composition, ownership, and mapped-root examples.
import DerivedKeysUI
import DerivedKeysUIExample
import UIKit

@MainActor
func readmeMeasurements(view: DocumentContentView) {
    let textSizes = SizeCache<UITextView>(
        dependingOn: \.text,
        \.font,
        \.textContainer.maximumNumberOfLines,
        capacity: 256
    )

    let availableSize = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
    let size = textSizes.size(of: view.textView, toFit: availableSize)

    let buttonSizes = SizeCache<UIButton>(
        dependingOn: \.currentTitle,
        \.titleLabel?.font,
        capacity: 256
    )
    let textSizing = textSizes.bound(to: \DocumentContentView.textView)
    let buttonSizing = buttonSizes.bound(to: \DocumentContentView.button)

    let contentSizes = SizeCache<DocumentContentView>(
        dependingOn: \.padding,
        \.spacing,
        \.showsButton,
        children: textSizing,
        buttonSizing,
        capacity: 256
    ) { content, proposal in
        let innerProposal = CGSize(
            width: max(0, proposal.width - 2 * content.padding),
            height: CGFloat.greatestFiniteMagnitude
        )
        let textSize = textSizing.size(of: content, toFit: innerProposal)
        let buttonSize =
            content.showsButton
            ? buttonSizing.size(of: content, toFit: innerProposal)
            : .zero
        return CGSize(
            width: proposal.width,
            height: 2 * content.padding + textSize.height + buttonSize.height
                + (content.showsButton ? content.spacing : 0)
        )
    }

    let initial = contentSizes.size(of: view, toFit: availableSize)
    view.spacing += 4
    let spaced = contentSizes.size(of: view, toFit: availableSize)  // Parent miss; children hit.
    view.content += " Another paragraph."
    let edited = contentSizes.size(of: view, toFit: availableSize)  // Parent and text miss; button hits.

    _ = (size, initial, spaced, edited)
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
func makePairSizes(titleSizes: SizeCache<UILabel>) -> SizeCache<PairView> {
    let titleSizing = titleSizes.bound(to: \PairView.title)
    let subtitleSizing = titleSizes.bound(to: \PairView.subtitle)
    return SizeCache<PairView>(
        children: titleSizing,
        subtitleSizing,
        capacity: 128
    ) { pair, proposal in
        let titleSize = titleSizing.size(of: pair, toFit: proposal)
        let subtitleSize = subtitleSizing.size(of: pair, toFit: proposal)
        return CGSize(
            width: max(titleSize.width, subtitleSize.width),
            height: titleSize.height + subtitleSize.height
        )
    }
}

// Minimal root for the guide's sizing composition; frame assignment is application-owned.
@MainActor
final class DocumentCardView: UIView {
    let headerLabel = UILabel()
    let contentView: DocumentContentView
    var spacing: CGFloat = 12

    init(contentView: DocumentContentView) {
        self.contentView = contentView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(contentView:).") }
}

@MainActor
func makeCardSizes(
    headerSizes: SizeCache<UILabel>,
    contentSizes: SizeCache<DocumentContentView>
) -> SizeCache<DocumentCardView> {
    let headerSizing = headerSizes.bound(to: \DocumentCardView.headerLabel)
    let contentSizing = contentSizes.bound(to: \DocumentCardView.contentView)
    return SizeCache<DocumentCardView>(
        dependingOn: \.spacing,
        children: headerSizing,
        contentSizing,
        capacity: 128
    ) { card, proposal in
        let childProposal = CGSize(
            width: proposal.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let headerSize = headerSizing.size(of: card, toFit: childProposal)
        let contentSize = contentSizing.size(of: card, toFit: childProposal)
        return CGSize(
            width: proposal.width,
            height: headerSize.height + card.spacing + contentSize.height
        )
    }
}

@MainActor
func readmeCardMeasurement() {
    let documentCaches = DocumentSizeCaches()
    let card = DocumentCardView(contentView: DocumentContentView(content: "Document", caches: documentCaches))
    card.headerLabel.text = "Header"
    let headerSizes = makeTitleSizes()
    let cardSizes = makeCardSizes(headerSizes: headerSizes, contentSizes: documentCaches.contentSizes)
    let cardSize = cardSizes.size(
        of: card,
        toFit: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
    )
    _ = cardSize
}
