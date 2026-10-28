#if canImport(UIKit)
import DerivedKeysUIExample
import Testing
import UIKit

@MainActor
struct DocumentContentViewTests {
    private let paragraph = String(repeating: "A document contains enough text to wrap onto many lines. ", count: 12)
    private let proposal = CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude)

    @Test func directLeafFittingAndParentLayoutUseTheSameGeometry() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let inner = CGSize(width: 196, height: CGFloat.greatestFiniteMagnitude)
        let text = caches.textSizes.size(of: view, toFit: inner)
        let button = caches.buttonSizes.size(of: view, toFit: inner)
        #expect(view.textView.text == paragraph)
        #expect(view.textView.textContainer.maximumNumberOfLines == 3)
        #expect(text.height > 0)
        #expect(button.height > 0)
        let fitted = view.sizeThatFits(proposal)
        #expect(fitted == CGSize(width: 220, height: 24 + text.height + 8 + button.height))
        view.frame = CGRect(origin: .zero, size: fitted)
        view.bounds.origin = CGPoint(x: 4, y: 7)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(view.textView.frame == CGRect(x: 16, y: 19, width: 196, height: text.height))
        #expect(view.button.frame == CGRect(x: 16, y: 27 + text.height, width: 196, height: button.height))
        #expect(view.button.frame.maxY + view.padding == view.bounds.maxY)
        #expect(caches.textSizes.count == 1)
        #expect(caches.buttonSizes.count == 1)
        #expect(caches.contentSizes.count == 1)
    }

    @Test func spacingChangesOnlyTheParentAndPaintChangesNoDescription() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let original = view.sizeThatFits(proposal)
        view.spacing += 11
        let spaced = view.sizeThatFits(proposal)
        #expect(spaced.height == original.height + 11)
        #expect(caches.contentSizes.count == 2)
        #expect(caches.textSizes.count == 1)
        #expect(caches.buttonSizes.count == 1)
        let snapshot = caches.contentSizes.snapshot(of: view)
        view.isSelectedForEditing = true
        #expect(caches.contentSizes.snapshot(of: view) == snapshot)
        #expect(view.sizeThatFits(proposal) == spaced)
        #expect(caches.contentSizes.count == 2)
    }

    @Test func contentAndExpansionChangesInvalidateTextAndParentButReuseButton() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: "Short", caches: caches)
        let short = view.sizeThatFits(proposal)
        view.content = paragraph
        let collapsed = view.sizeThatFits(proposal)
        #expect(collapsed.height > short.height)
        #expect(view.textView.text == paragraph)
        #expect(caches.textSizes.count == 2)
        #expect(caches.contentSizes.count == 2)
        #expect(caches.buttonSizes.count == 1)
        view.isExpanded = true
        let expanded = view.sizeThatFits(proposal)
        #expect(expanded.height > collapsed.height)
        #expect(view.textView.textContainer.maximumNumberOfLines == 0)
        #expect(caches.textSizes.count == 3)
        #expect(caches.contentSizes.count == 3)
        #expect(caches.buttonSizes.count == 1)
    }

    @Test func hiddenButtonSkipsMeasurementButItsDescriptionRemainsConservative() throws {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let visible = view.sizeThatFits(proposal)
        let buttonHeight = view.button.sizeThatFits(CGSize(width: 196, height: CGFloat.greatestFiniteMagnitude)).height
        view.showsButton = false
        let hidden = view.sizeThatFits(proposal)
        #expect(hidden.height == visible.height - view.spacing - buttonHeight)
        #expect(caches.textSizes.count == 1)
        #expect(caches.buttonSizes.count == 1)
        #expect(caches.contentSizes.count == 2)
        view.frame = CGRect(origin: .zero, size: hidden)
        view.layoutIfNeeded()
        #expect(view.button.isHidden)
        #expect(view.button.frame == .zero)
        let before = caches.contentSizes.snapshot(of: view)
        let host = UIViewController()
        let child = UIViewController()
        host.addChild(child)
        child.view.addSubview(view)
        setCategory(.accessibilityExtraExtraExtraLarge, for: child, in: host)
        try #require(view.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
        #expect(caches.contentSizes.snapshot(of: view) != before)
        let larger = view.sizeThatFits(proposal)
        #expect(larger.height > hidden.height)
        #expect(caches.contentSizes.count == 3)
        #expect(caches.textSizes.count == 2)
        // The hidden button's category is captured, but no new button result is requested.
        #expect(caches.buttonSizes.count == 1)
        #expect(
            view.textView.font
                == UIFont.preferredFont(
                    forTextStyle: .body,
                    compatibleWith: UITraitCollection(
                        preferredContentSizeCategory: view.traitCollection.preferredContentSizeCategory
                    )
                )
        )
        #expect(
            view.button.titleLabel?.font
                == UIFont.preferredFont(
                    forTextStyle: .body,
                    compatibleWith: UITraitCollection(
                        preferredContentSizeCategory: view.traitCollection.preferredContentSizeCategory
                    )
                )
        )
    }

    @Test func equivalentViewsReuseInjectedStorageWithoutSharingControlsOrRetainingRoots() {
        let caches = DocumentSizeCaches()
        var first: DocumentContentView? = DocumentContentView(content: paragraph, caches: caches)
        weak let weakFirst = first
        let fitted = first?.sizeThatFits(proposal)
        first = nil
        #expect(weakFirst == nil)
        let second = DocumentContentView(content: paragraph, caches: caches)
        #expect(second.sizeThatFits(proposal) == fitted)
        second.frame = CGRect(origin: .zero, size: second.sizeThatFits(proposal))
        second.layoutIfNeeded()
        #expect(second.textView.text == paragraph)
        #expect(caches.contentSizes.count == 1)
        #expect(caches.textSizes.count == 1)
        #expect(caches.buttonSizes.count == 1)
        let independent = DocumentSizeCaches()
        #expect(independent.contentSizes.count == 0)
        #expect(independent.textSizes.count == 0)
        #expect(independent.buttonSizes.count == 0)
    }

    @Test func directLeafRequestsSynchronizeTypographyAfterCategoryChanges() throws {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let inner = CGSize(width: 196, height: CGFloat.greatestFiniteMagnitude)
        let initialText = caches.textSizes.size(of: view, toFit: inner)
        let initialButton = caches.buttonSizes.size(of: view, toFit: inner)
        let host = UIViewController()
        let child = UIViewController()
        host.addChild(child)
        child.view.addSubview(view)
        setCategory(.accessibilityExtraExtraExtraLarge, for: child, in: host)
        try #require(view.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
        let largeText = caches.textSizes.size(of: view, toFit: inner)
        let largeButton = caches.buttonSizes.size(of: view, toFit: inner)
        #expect(largeText.height > initialText.height)
        #expect(largeButton.height > initialButton.height)
        #expect(caches.textSizes.count == 2)
        #expect(caches.buttonSizes.count == 2)
        #expect(caches.contentSizes.count == 0)
    }

    @Test func outerProposalChangesDoNotChangeTheInnerHeightProposal() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let first = view.sizeThatFits(proposal)
        #expect(view.sizeThatFits(CGSize(width: proposal.width, height: 1)) == first)
        #expect(caches.contentSizes.count == 2)
        #expect(caches.textSizes.count == 1)
        #expect(caches.buttonSizes.count == 1)
    }

    private func setCategory(_ category: UIContentSizeCategory, for child: UIViewController, in host: UIViewController)
    {
        if #available(iOS 17, *) {
            child.traitOverrides.preferredContentSizeCategory = category
            child.updateTraitsIfNeeded()
        } else {
            host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: child)
        }
    }
}
#endif
