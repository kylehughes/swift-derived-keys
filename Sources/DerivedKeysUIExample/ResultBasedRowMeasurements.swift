#if canImport(UIKit)
import DerivedKeys
import DerivedKeysUI
import UIKit

/// Application-owned, two-stage measurement for plain-text rows on a uniform line grid.
///
/// A screen can retain one bundle and pass its authoritative model strings directly.
/// The first cache selects text and width; the second selects only the resulting line
/// count. Different strings can therefore share a height entry without sharing a text
/// measurement entry. The height formula illustrates result-based reuse, not a claim
/// that caching this inexpensive arithmetic improves performance.
///
/// Font, line height, padding, word wrapping, and unlimited lines stay fixed for the
/// bundle's lifetime. Create a new bundle when typography changes, including resolved
/// Dynamic Type changes. Rendering must use the same font, zero horizontal text padding,
/// and uniform line grid. Attributed text, attachments, and variable line heights are
/// outside this example's policy.
///
/// The screen owns the bundle; the cache's recipe retains only the private TextKit
/// helper, so it does not capture the screen or the bundle itself.
@MainActor
public final class ResultBasedRowMeasurements {
    /// The fixed font used for every text measurement.
    public let font: UIFont
    /// The fixed height assigned to each line, in points.
    public let lineHeight: CGFloat
    /// The total fixed padding above and below a row's text, in points.
    public let verticalPadding: CGFloat

    private let lineCounter: PlainTextLineCounter
    private let lineCounts: MainActorResultCache<(text: String, width: CGFloat), Int>
    private var rowHeights: ResultCache<Int, CGFloat>

    /// The number of first-stage computations, including empty-text computations.
    public var lineCountCalculationCount: Int {
        lineCounter.calculationCount
    }

    /// The number of retained text-and-width results.
    public var lineCountEntryCount: Int {
        lineCounts.count
    }

    /// The number of retained heights, keyed only by line count.
    public var rowHeightEntryCount: Int {
        rowHeights.count
    }

    /// Creates independently bounded caches with a fixed plain-text layout policy.
    ///
    /// - Precondition: Capacities are nonnegative, `lineHeight` is finite and at least
    ///   the font's natural line height, and `verticalPadding` is finite and nonnegative.
    public init(
        font: UIFont = .systemFont(ofSize: 16),
        lineHeight: CGFloat = 24,
        verticalPadding: CGFloat = 16,
        lineCountCapacity: Int = 256,
        rowHeightCapacity: Int = 32
    ) {
        precondition(lineHeight.isFinite && lineHeight >= font.lineHeight)
        precondition(verticalPadding.isFinite && verticalPadding >= 0)
        self.font = font
        self.lineHeight = lineHeight
        self.verticalPadding = verticalPadding
        let lineCounter = PlainTextLineCounter(font: font, lineHeight: lineHeight)
        self.lineCounter = lineCounter
        lineCounts = MainActorResultCache(
            dependingOn: \.text,
            \.width,
            capacity: lineCountCapacity
        ) { input in
            lineCounter.count(text: input.text, width: input.width)
        }
        rowHeights = ResultCache(dependingOn: \.self, capacity: rowHeightCapacity) { count in
            CGFloat(count) * lineHeight + verticalPadding
        }
    }

    /// Returns the height obtained by passing the cached line count into the height cache.
    ///
    /// Empty text has zero lines and a height equal to `verticalPadding`. A final
    /// paragraph separator in nonempty text contributes its final empty line.
    /// - Precondition: `width` is finite and positive, measured inside any horizontal padding.
    public func height(for text: String, width: CGFloat) -> CGFloat {
        precondition(width.isFinite && width > 0)
        let count = lineCounts.value(for: (text: text, width: width))
        let height = rowHeights.value(for: count)
        return height
    }

    /// Returns a cached TextKit line count for an authoritative model string and width.
    ///
    /// - Precondition: `width` is finite and positive, measured inside any horizontal padding.
    public func lineCount(for text: String, width: CGFloat) -> Int {
        precondition(width.isFinite && width > 0)
        return lineCounts.value(for: (text: text, width: width))
    }
}

@MainActor
private final class PlainTextLineCounter {
    private let attributes: [NSAttributedString.Key: Any]
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let textStorage: NSTextStorage

    private(set) var calculationCount = 0

    init(font: UIFont, lineHeight: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        attributes = [.font: font, .paragraphStyle: paragraph]
        layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false
        textContainer = NSTextContainer(size: .zero)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
    }

    func count(text: String, width: CGFloat) -> Int {
        calculationCount += 1
        guard !text.isEmpty else { return 0 }
        textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
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
