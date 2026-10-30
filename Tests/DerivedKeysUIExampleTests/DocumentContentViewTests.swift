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
        #expect(view.textView.text == paragraph)
        #expect(view.textView.textContainer.maximumNumberOfLines == 3)
        #expect(view.textView.font == preferredFont(for: view))
        #expect(view.button.titleLabel?.font == preferredFont(for: view))
        #expect(view.button.currentTitle == "Show more")
        #expect(!view.textView.adjustsFontForContentSizeCategory)
        #expect(view.button.titleLabel?.adjustsFontForContentSizeCategory == false)
        let text = caches.textSizes.size(of: view.textView, toFit: inner)
        let button = caches.buttonSizes.size(of: view.button, toFit: inner)
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
        #expect(view.textView.text == paragraph)
        let collapsed = view.sizeThatFits(proposal)
        #expect(collapsed.height > short.height)
        #expect(view.textView.text == paragraph)
        #expect(caches.textSizes.count == 2)
        #expect(caches.contentSizes.count == 2)
        #expect(caches.buttonSizes.count == 1)
        view.isExpanded = true
        #expect(view.textView.textContainer.maximumNumberOfLines == 0)
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
        #expect(view.textView.font == preferredFont(for: view))
        #expect(view.button.titleLabel?.font == preferredFont(for: view))
        #expect(caches.contentSizes.snapshot(of: view) != before)
        let larger = view.sizeThatFits(proposal)
        #expect(larger.height > hidden.height)
        #expect(caches.contentSizes.count == 3)
        #expect(caches.textSizes.count == 2)
        // The hidden button’s updated font is captured, but no new button result is requested.
        #expect(caches.buttonSizes.count == 1)
        #expect(view.textView.font == preferredFont(for: view))
        #expect(view.button.titleLabel?.font == preferredFont(for: view))
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

    @Test func traitChangesUpdateBothControlsBeforeDirectLeafRequests() throws {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let inner = CGSize(width: 196, height: CGFloat.greatestFiniteMagnitude)
        let initialText = caches.textSizes.size(of: view.textView, toFit: inner)
        let initialButton = caches.buttonSizes.size(of: view.button, toFit: inner)
        let text = view.textView
        let button = view.button
        text.font = .systemFont(ofSize: 11)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        let host = UIViewController()
        let child = UIViewController()
        host.addChild(child)
        child.view.addSubview(view)
        setCategory(.accessibilityExtraExtraExtraLarge, for: child, in: host)
        try #require(view.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
        #expect(view.textView.font == preferredFont(for: view))
        #expect(view.button.titleLabel?.font == preferredFont(for: view))
        #expect(text.font == preferredFont(for: view))
        #expect(button.titleLabel?.font == preferredFont(for: view))
        let largeText = caches.textSizes.size(of: text, toFit: inner)
        let largeButton = caches.buttonSizes.size(of: button, toFit: inner)
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

    @Test func retainedControlAliasesInvalidateSelectedValuesWithoutReadSideEffects() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: "Short", caches: caches)
        let text = view.textView
        let button = view.button
        let inner = CGSize(width: 196, height: CGFloat.greatestFiniteMagnitude)
        _ = view.sizeThatFits(proposal)
        var previous = caches.contentSizes.snapshot(of: view)

        text.text = paragraph
        #expect(caches.contentSizes.snapshot(of: view) != previous)
        #expect(view.textView === text)
        #expect(text.text == paragraph)
        #expect(caches.textSizes.size(of: text, toFit: inner) == text.sizeThatFits(inner))
        #expect(view.sizeThatFits(proposal) == directSize(of: view, inner: inner))
        previous = caches.contentSizes.snapshot(of: view)

        text.font = .systemFont(ofSize: 31)
        #expect(caches.contentSizes.snapshot(of: view) != previous)
        #expect(text.font == UIFont.systemFont(ofSize: 31))
        #expect(caches.textSizes.size(of: text, toFit: inner) == text.sizeThatFits(inner))
        #expect(view.sizeThatFits(proposal) == directSize(of: view, inner: inner))
        previous = caches.contentSizes.snapshot(of: view)

        text.textContainer.maximumNumberOfLines = 1
        #expect(caches.contentSizes.snapshot(of: view) != previous)
        #expect(text.textContainer.maximumNumberOfLines == 1)
        #expect(caches.textSizes.size(of: text, toFit: inner) == text.sizeThatFits(inner))
        #expect(view.sizeThatFits(proposal) == directSize(of: view, inner: inner))
        previous = caches.contentSizes.snapshot(of: view)

        button.setTitle("A different button title", for: .normal)
        #expect(caches.contentSizes.snapshot(of: view) != previous)
        #expect(view.button === button)
        #expect(button.currentTitle == "A different button title")
        #expect(caches.buttonSizes.size(of: button, toFit: inner) == button.sizeThatFits(inner))
        #expect(view.sizeThatFits(proposal) == directSize(of: view, inner: inner))
        previous = caches.contentSizes.snapshot(of: view)

        button.titleLabel?.font = .systemFont(ofSize: 29)
        #expect(caches.contentSizes.snapshot(of: view) != previous)
        #expect(button.titleLabel?.font == UIFont.systemFont(ofSize: 29))
        #expect(caches.buttonSizes.size(of: button, toFit: inner) == button.sizeThatFits(inner))
        let expected = directSize(of: view, inner: inner)
        #expect(view.sizeThatFits(proposal) == expected)
        #expect(caches.contentSizes.count == 6)

        view.content = "Restored"
        #expect(text.text == "Restored")
        #expect(text.font == UIFont.systemFont(ofSize: 31))
        view.isExpanded = true
        #expect(text.textContainer.maximumNumberOfLines == 0)
        #expect(button.currentTitle == "A different button title")
    }

    @Test func gettersAndSnapshotsLeaveUnselectedFixedSettingsUntouched() {
        let caches = DocumentSizeCaches()
        let view = DocumentContentView(content: paragraph, caches: caches)
        let text = view.textView
        let button = view.button
        let snapshot = caches.contentSizes.snapshot(of: view)
        // These settings are a caller-owned fixed contract, not automatically tracked inputs.
        text.textContainer.lineFragmentPadding = 7
        text.textContainerInset = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        button.semanticContentAttribute = .forceRightToLeft
        #expect(view.textView === text)
        #expect(view.button === button)
        #expect(caches.contentSizes.snapshot(of: view) == snapshot)
        #expect(text.textContainer.lineFragmentPadding == 7)
        #expect(text.textContainerInset == UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
        #expect(button.semanticContentAttribute == .forceRightToLeft)
    }

    private func directSize(of view: DocumentContentView, inner: CGSize) -> CGSize {
        CGSize(
            width: proposal.width,
            height: 2 * view.padding + view.textView.sizeThatFits(inner).height + view.spacing
                + view.button.sizeThatFits(inner).height
        )
    }

    private func preferredFont(for view: DocumentContentView) -> UIFont {
        .preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: view.traitCollection.preferredContentSizeCategory
            )
        )
    }

    private func setCategory(_ category: UIContentSizeCategory, for child: UIViewController, in host: UIViewController)
    {
        if #available(iOS 17, *) {
            child.traitOverrides.preferredContentSizeCategory = category
            child.updateTraitsIfNeeded()
            child.view.updateTraitsIfNeeded()
            for view in child.view.subviews { view.updateTraitsIfNeeded() }
        } else {
            host.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: child)
        }
    }
}
#endif
