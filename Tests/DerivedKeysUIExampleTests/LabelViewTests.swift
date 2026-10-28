#if canImport(UIKit)
import DerivedKeysUIExample
import Testing
import UIKit

@MainActor
struct LabelViewTests {
    private let paragraph = "A long paragraph with enough words to wrap across several lines in a narrow container."

    @Test func fittingAndFrameLayoutReuseTheCompleteResult() throws {
        let view = LabelView(text: paragraph)
        let fitted = view.sizeThatFits(CGSize(width: 180, height: 1))
        view.frame = CGRect(origin: .zero, size: fitted)
        view.bounds.origin = CGPoint(x: 7, y: 9)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let label = try #require(view.subviews.first as? UILabel)
        #expect(view.calculationCount == 1)
        #expect(fitted.width == 180)
        #expect(fitted.height > 24)
        #expect(label.frame == CGRect(x: 19, y: 21, width: 156, height: fitted.height - 24))
        #expect(label.text == paragraph)
        #expect(label.font == UIFont.systemFont(ofSize: 17))
        #expect(label.numberOfLines == 0)
        #expect(label.lineBreakMode == .byWordWrapping)
        #expect(label.semanticContentAttribute == .forceLeftToRight)
    }

    @Test func widthAndTextChangesRecomputeAndPreviousTextReusesItsEntry() {
        let view = LabelView(text: paragraph)
        let narrow = view.sizeThatFits(CGSize(width: 100, height: 0))
        let wide = view.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        #expect(narrow.height > wide.height)
        #expect(view.calculationCount == 2)
        view.text = "Short"
        let short = view.sizeThatFits(CGSize(width: 100, height: 0))
        #expect(short.height < narrow.height)
        #expect(view.calculationCount == 3)
        view.text = paragraph
        #expect(view.sizeThatFits(CGSize(width: 100, height: CGFloat.nan)) == narrow)
        #expect(view.calculationCount == 3)
    }

    @Test func changingTextSchedulesLayoutAndParentRefittingReusesTheResult() throws {
        let view = LabelView(text: "Short")
        let originalSize = view.sizeThatFits(CGSize(width: 100, height: 0))
        view.frame = CGRect(origin: .zero, size: originalSize)
        view.layoutIfNeeded()
        let label = try #require(view.subviews.first as? UILabel)
        let originalFrame = label.frame

        view.text = paragraph
        // The parent has not changed the frame: only the text setter schedules this pass.
        view.layoutIfNeeded()
        #expect(label.text == paragraph)
        #expect(label.frame.height > originalFrame.height)
        #expect(view.calculationCount == 2)

        let fitted = view.sizeThatFits(CGSize(width: 100, height: 0))
        view.frame = CGRect(origin: .zero, size: fitted)
        view.layoutIfNeeded()
        #expect(fitted.height > originalSize.height)
        #expect(label.frame == CGRect(x: 12, y: 12, width: 76, height: fitted.height - 24))
        #expect(view.calculationCount == 2)
    }

    @Test func paintOnlyChangesReuseTheLayout() throws {
        let view = LabelView(text: paragraph)
        let fitted = view.sizeThatFits(CGSize(width: 180, height: 0))
        view.textColor = .red
        view.frame = CGRect(origin: .zero, size: fitted)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let label = try #require(view.subviews.first as? UILabel)
        #expect(label.textColor == .red)
        #expect(view.calculationCount == 1)
    }

    @Test func equivalentViewsShareEntriesWithoutSharingDisplayedLabels() throws {
        let cache = LabelView.Cache(capacity: 4)
        let first = LabelView(text: paragraph, cache: cache)
        let second = LabelView(text: paragraph, cache: cache)
        let size = first.sizeThatFits(CGSize(width: 180, height: 0))
        second.frame = CGRect(origin: .zero, size: size)
        second.setNeedsLayout()
        second.layoutIfNeeded()
        let label = try #require(second.subviews.first as? UILabel)
        #expect(first.calculationCount == 1)
        #expect(second.calculationCount == 0)
        #expect(cache.count == 1)
        #expect(label.text == paragraph)
        #expect(label.frame == CGRect(x: 12, y: 12, width: 156, height: size.height - 24))
    }

    @Test func narrowWidthsKeepFramesNonnegativeAndCacheCapacityIsBounded() throws {
        let cache = LabelView.Cache(capacity: 2)
        let view = LabelView(text: paragraph, cache: cache)
        for width: CGFloat in [0, 8, 24] {
            let size = view.sizeThatFits(CGSize(width: width, height: 0))
            view.frame = CGRect(origin: .zero, size: size)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let label = try #require(view.subviews.first as? UILabel)
            #expect(size == CGSize(width: width, height: 24))
            #expect(label.frame.width == 0)
            #expect(label.frame.minX >= 0)
            #expect(label.frame.maxX <= width)
        }
        #expect(cache.count == 2)
        #expect(view.calculationCount == 3)
        _ = view.sizeThatFits(CGSize(width: 0, height: 0))
        #expect(view.calculationCount == 4)
    }

    @Test func invalidWidthsDoNotEnterTheCache() {
        let cache = LabelView.Cache(capacity: 4)
        let view = LabelView(text: paragraph, cache: cache)
        for width: CGFloat in [-1, .nan, .infinity, -.infinity] {
            #expect(view.sizeThatFits(CGSize(width: width, height: 0)) == .zero)
        }
        #expect(cache.count == 0)
        #expect(view.calculationCount == 0)
    }

    @Test func unconstrainedWidthReturnsFiniteNaturalSize() throws {
        let view = LabelView(text: "Natural width")
        let size = view.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        #expect(size.width.isFinite && size.width > 24 && size.width < 1000)
        #expect(size.height.isFinite && size.height > 24 && size.height < 1000)
        view.frame = CGRect(origin: .zero, size: size)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let label = try #require(view.subviews.first as? UILabel)
        #expect(label.frame.width == size.width - 24)
        // Natural-width fitting and the parent's finite assigned width are distinct proposals.
        #expect(view.calculationCount == 2)
    }
}
#endif
