#if canImport(UIKit)
import DerivedKeysUI
import UIKit

/// A two-stage measurement bundle for plain-text rows that fill the proposed width.
///
/// The first stage caches rendered TextKit line counts by native model text, inner width,
/// and font. The second keys that count alongside font, padding, and the fitting proposal,
/// calling the row's `sizeThatFits(_:)` on a miss. Distinct strings can share a measured size
/// when their line counts and remaining layout inputs match. This reuse assumes the row's
/// uniform plain-text layout; rich text and attachments are outside the example.
///
/// A screen can share one bundle across reusable rows. Entries do not implicitly retain
/// rows: the first recipe captures only the private line counter, and the second measures
/// the row supplied to the current call.
@MainActor
public final class ResultBasedRowMeasurements {
    private let lineCounter: PlainTextLineCounter
    private let lineCounts: MainActorResultCache<(text: String, width: CGFloat, font: UIFont), Int>
    private let rowSizes: SizeCache<(view: PlainTextRowView, lineCount: Int)>

    /// The number of first-stage calculations, including empty text.
    public var lineCountCalculationCount: Int { lineCounter.calculationCount }

    /// The number of retained text, inner-width, and font results.
    public var lineCountEntryCount: Int { lineCounts.count }

    /// The number of retained row sizes.
    public var rowSizeEntryCount: Int { rowSizes.count }

    /// Creates independently bounded caches; zero capacity disables storage in that stage.
    ///
    /// - Precondition: Both capacities are nonnegative.
    public init(lineCountCapacity: Int = 256, rowSizeCapacity: Int = 32) {
        let lineCounter = PlainTextLineCounter()
        self.lineCounter = lineCounter
        lineCounts = MainActorResultCache(
            dependingOn: \.text,
            \.width,
            \.font,
            capacity: lineCountCapacity
        ) { input in
            lineCounter.count(text: input.text, width: input.width, font: input.font)
        }
        rowSizes = SizeCache(
            dependingOn: \.lineCount,
            \.view.font,
            \.view.horizontalPadding,
            \.view.verticalPadding,
            capacity: rowSizeCapacity
        ) { input, proposal in
            input.view.sizeThatFits(proposal)
        }
    }

    /// Returns a cached rendered line count for plain text at its inner width.
    ///
    /// Empty text includes the text view's empty editing line. A trailing newline contributes
    /// an additional empty line. The font and wrapping match `PlainTextRowView`.
    /// - Precondition: `width` is finite, positive, and less than greatest finite magnitude.
    public func lineCount(for text: String, width: CGFloat, font: UIFont) -> Int {
        precondition(width.isFinite && width > 0 && width < CGFloat.greatestFiniteMagnitude)
        return lineCounts.value(for: (text: text, width: width, font: font))
    }

    /// Resolves the line count, then looks up the row size using the current view.
    ///
    /// The row's native text and private text view are synchronized before either stage.
    /// Both proposal axes enter the second key, although the row ignores proposed height.
    /// The caller remains responsible for assigning the returned outer frame.
    /// - Precondition: The proposal has a finite positive width with positive inner width,
    ///   no unconstrained-width sentinel, and a finite nonnegative height.
    public func size(of row: PlainTextRowView, toFit proposal: CGSize) -> CGSize {
        let count = lineCount(for: row.text, width: row.textWidth(for: proposal.width), font: row.font)
        return rowSizes.size(of: (view: row, lineCount: count), toFit: proposal)
    }
}

/// A plain-text row with uniform typography whose fitted size fills the proposed width.
///
/// A private TextKit 1 `UITextView` renders the text with natural line heights, word wrapping,
/// unlimited lines, and zero text insets or fragment padding. All formatting other than font
/// stays fixed. Updating `text` or `font` synchronizes the text view and schedules layout;
/// the caller must request a new size and assign the row's frame. `sizeThatFits(_:)` measures
/// the text view directly and never calls back into `ResultBasedRowMeasurements`.
@MainActor
public final class PlainTextRowView: UIView {
    private let textView = UITextView(usingTextLayoutManager: false)

    /// The uniform font, selected independently by both cache stages.
    public var font: UIFont {
        didSet { synchronizeText() }
    }

    /// Padding on each horizontal side, in points.
    ///
    /// - Precondition: The value is finite and nonnegative.
    public var horizontalPadding: CGFloat {
        didSet {
            precondition(horizontalPadding.isFinite && horizontalPadding >= 0)
            setNeedsLayout()
        }
    }

    /// The number of actual fitting calls, including direct measurements outside the cache.
    public private(set) var sizeThatFitsCallCount = 0

    /// The native model text; cache keys never read it back from the text view.
    public var text: String {
        didSet { synchronizeText() }
    }

    /// Padding on each vertical side, in points.
    ///
    /// - Precondition: The value is finite and nonnegative.
    public var verticalPadding: CGFloat {
        didSet {
            precondition(verticalPadding.isFinite && verticalPadding >= 0)
            setNeedsLayout()
        }
    }

    /// Creates a row with a fixed plain-text rendering policy and variable font and padding.
    ///
    /// - Precondition: Padding values are finite and nonnegative.
    public init(
        text: String = "",
        font: UIFont = .systemFont(ofSize: 16),
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 8
    ) {
        precondition(horizontalPadding.isFinite && horizontalPadding >= 0)
        precondition(verticalPadding.isFinite && verticalPadding >= 0)
        self.text = text
        self.font = font
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)
        configureTextView()
    }

    /// Creates a decoded row with empty text and default typography and padding.
    public required init?(coder: NSCoder) {
        text = ""
        font = .systemFont(ofSize: 16)
        horizontalPadding = 0
        verticalPadding = 8
        super.init(coder: coder)
        configureTextView()
    }

    /// Positions the private text view inside the row's current bounds.
    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width - horizontalPadding * 2)
        textView.frame = CGRect(
            x: bounds.minX + horizontalPadding,
            y: bounds.minY + verticalPadding,
            width: width,
            height: max(0, bounds.height - verticalPadding * 2)
        )
        textView.textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }

    /// Measures the actual text view at the inner width and fills the supplied outer width.
    ///
    /// Proposed height is ignored. No height is calculated from the number of lines.
    /// - Precondition: The width is finite, positive, below greatest finite magnitude,
    ///   and leaves positive inner width after padding.
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = textWidth(for: size.width)
        sizeThatFitsCallCount += 1
        textView.textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let measured = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: size.width, height: measured.height + verticalPadding * 2)
    }

    fileprivate static func attributedText(_ text: String, font: UIFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
    }

    fileprivate func textWidth(for width: CGFloat) -> CGFloat {
        precondition(width.isFinite && width > 0 && width < CGFloat.greatestFiniteMagnitude)
        let innerWidth = width - horizontalPadding * 2
        precondition(innerWidth.isFinite && innerWidth > 0)
        return innerWidth
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        addSubview(textView)
        synchronizeText()
    }

    private func synchronizeText() {
        textView.attributedText = Self.attributedText(text, font: font)
        textView.font = font
        setNeedsLayout()
    }
}

@MainActor
private final class PlainTextLineCounter {
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private let textStorage = NSTextStorage()

    private(set) var calculationCount = 0

    init() {
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
    }

    func count(text: String, width: CGFloat, font: UIFont) -> Int {
        calculationCount += 1
        // An empty UITextView still displays its empty editing line.
        guard !text.isEmpty else { return 1 }
        textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textStorage.setAttributedString(PlainTextRowView.attributedText(text, font: font))
        layoutManager.ensureLayout(for: textContainer)
        var count = 0
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) {
            _,
            _,
            _,
            _,
            _ in
            count += 1
        }
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            count += 1
        }
        return count
    }
}
#endif
