#if canImport(UIKit)
import DerivedKeysUI
import UIKit

/// Screen-owned caches for this example's fixed text, button, and frame-layout recipes.
///
/// Closures retain only the child handles they call. Equal semantic inputs can reuse
/// sizes across views; the bundle does not retain a view or controller.
@MainActor
public final class DocumentSizeCaches {
    /// Text sizes selected by the control's text, font, and maximum line count.
    public let textSizes: SizeCache<UITextView>
    /// Button sizes selected by the control's current title and title font.
    public let buttonSizes: SizeCache<UIButton>
    /// Complete sizes selected by local layout values and both child descriptions.
    public let contentSizes: SizeCache<DocumentContentView>

    /// Creates independent bounded storage for each recipe.
    public init(capacity: Int = 256) {
        let textSizes = SizeCache<UITextView>(
            dependingOn: \.text,
            \.font,
            \.textContainer.maximumNumberOfLines,
            capacity: capacity
        )
        let buttonSizes = SizeCache<UIButton>(
            dependingOn: \.currentTitle,
            \.titleLabel?.font,
            capacity: capacity
        )
        let text = textSizes.bound(to: \DocumentContentView.textView)
        let button = buttonSizes.bound(to: \DocumentContentView.button)
        self.textSizes = textSizes
        self.buttonSizes = buttonSizes
        contentSizes = SizeCache<DocumentContentView>(
            dependingOn: \.padding,
            \.spacing,
            \.showsButton,
            children: text,
            button,
            capacity: capacity
        ) { view, proposal in
            let innerProposal = CGSize(
                width: max(0, proposal.width - 2 * view.padding),
                height: CGFloat.greatestFiniteMagnitude
            )
            let textSize = text.size(of: view, toFit: innerProposal)
            let buttonHeight = view.showsButton ? button.size(of: view, toFit: innerProposal).height : 0
            let gap = view.showsButton ? view.spacing : 0
            return CGSize(width: proposal.width, height: 2 * view.padding + textSize.height + gap + buttonHeight)
        }
    }
}

/// A reusable plain UIKit view with measurement caches injected by its screen.
///
/// Fitting fills the proposed width and computes an unconstrained height. Padding and
/// spacing must be finite and nonnegative. The parent owns refitting and assigning the
/// outer frame after input changes. The caches track the controls' text, fonts, maximum
/// line count, and current button title. Other measurement settings, including wrapping
/// and direction, must remain fixed. Model assignments restore their corresponding control
/// values, and category changes restore both fonts.
@MainActor
public final class DocumentContentView: UIView {
    private let caches: DocumentSizeCaches
    private let renderedText = UITextView()
    private let renderedButton = UIButton(type: .system)

    /// Plain text selected by the text recipe; changes schedule layout.
    public var content: String {
        didSet {
            renderedText.text = content
            setNeedsLayout()
        }
    }
    /// Whether the text shows all lines instead of at most three.
    public var isExpanded = false {
        didSet {
            renderedText.textContainer.maximumNumberOfLines = isExpanded ? 0 : 3
            setNeedsLayout()
        }
    }
    /// Equal padding on all four sides, in points.
    public var padding: CGFloat = 12 { didSet { setNeedsLayout() } }
    /// The gap before a visible button, in points.
    public var spacing: CGFloat = 8 { didSet { setNeedsLayout() } }
    /// Whether the button contributes to fitting and layout.
    public var showsButton = true { didSet { setNeedsLayout() } }
    /// Paint-only selection state, deliberately absent from every size description.
    public var isSelectedForEditing = false {
        didSet { backgroundColor = isSelectedForEditing ? .secondarySystemBackground : .clear }
    }

    /// The existing text control, read without changing its rendering state.
    public var textView: UITextView { renderedText }

    /// The existing button control, read without changing its rendering state.
    public var button: UIButton { renderedButton }

    /// Creates a reusable view using the screen's cache bundle.
    public init(content: String = "", caches: DocumentSizeCaches) {
        self.caches = caches
        self.content = content
        super.init(frame: .zero)
        configureControls()
        renderedText.text = content
        renderedText.textContainer.maximumNumberOfLines = isExpanded ? 0 : 3
        updateTypography()
    }

    /// Storyboard construction is unavailable because a screen must inject the caches.
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("Inject DocumentSizeCaches with init(content:caches:).") }

    /// Returns the complete cached fit for the supplied finite nonnegative proposal.
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        caches.contentSizes.size(of: self, toFit: size)
    }

    /// Places controls using the same child handles and inner proposal as fitting.
    public override func layoutSubviews() {
        super.layoutSubviews()
        let innerProposal = CGSize(width: max(0, bounds.width - 2 * padding), height: CGFloat.greatestFiniteMagnitude)
        let textSize = caches.textSizes.size(of: textView, toFit: innerProposal)
        let textView = textView
        textView.frame = CGRect(
            x: bounds.minX + padding,
            y: bounds.minY + padding,
            width: innerProposal.width,
            height: textSize.height
        )
        let button = button
        button.isHidden = !showsButton
        if showsButton {
            let buttonSize = caches.buttonSizes.size(of: button, toFit: innerProposal)
            button.frame = CGRect(
                x: bounds.minX + padding,
                y: textView.frame.maxY + spacing,
                width: innerProposal.width,
                height: buttonSize.height
            )
        } else {
            button.frame = .zero
        }
    }

    /// Updates both fonts and schedules layout when the content size category changes.
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateTypography()
            setNeedsLayout()
        }
    }

    private func updateTypography() {
        let font = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: traitCollection.preferredContentSizeCategory
            )
        )
        renderedText.font = font
        renderedButton.titleLabel?.font = font
    }

    private func configureControls() {
        renderedText.isScrollEnabled = false
        renderedText.isEditable = false
        renderedText.isSelectable = false
        renderedText.textContainerInset = .zero
        renderedText.textContainer.lineFragmentPadding = 0
        renderedText.textContainer.lineBreakMode = .byTruncatingTail
        renderedText.textAlignment = .left
        renderedText.semanticContentAttribute = .forceLeftToRight
        renderedText.adjustsFontForContentSizeCategory = false
        renderedButton.setTitle("Show more", for: .normal)
        renderedButton.titleLabel?.adjustsFontForContentSizeCategory = false
        renderedButton.semanticContentAttribute = .forceLeftToRight
        addSubview(renderedText)
        addSubview(renderedButton)
    }
}

/// An application-owned controller that shares one bundle and assigns the outer frame.
@MainActor
public final class DocumentScreen: UIViewController {
    /// The screen's shared recipe handles and bounded storage.
    public let sizeCaches: DocumentSizeCaches
    /// The reusable document view measured by this screen.
    public let contentView: DocumentContentView

    /// Creates a screen with its own bundle, without adding an application target.
    public init(content: String) {
        let sizeCaches = DocumentSizeCaches()
        self.sizeCaches = sizeCaches
        contentView = DocumentContentView(content: content, caches: sizeCaches)
        super.init(nibName: nil, bundle: nil)
    }

    /// Storyboard construction is unavailable for this programmatic example.
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("Use init(content:).") }

    /// Installs the reusable content view.
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(contentView)
    }

    /// Refits the outer view for the screen's current safe-area width.
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let available = view.bounds.inset(by: view.safeAreaInsets)
        let size = contentView.sizeThatFits(
            CGSize(width: max(0, available.width), height: CGFloat.greatestFiniteMagnitude)
        )
        contentView.frame = CGRect(origin: available.origin, size: size)
    }
}
#endif
