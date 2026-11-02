// Complete examples from the UI and UIKit DocC overviews and Examples/UI-Measurement.md.
import DerivedKeysUI
import DerivedKeysUIKit
import UIKit

@MainActor
func makeTextSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 256)
}

@MainActor
func measureText(using sizes: SizeCache<UILabel>) -> CGSize {
    let label = UILabel()
    label.text = "Unread messages"
    label.font = .systemFont(ofSize: 17)
    label.numberOfLines = 1
    return sizes.size(
        of: label,
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
    )
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

@MainActor
func measurePair(using sizes: SizeCache<PairView>) -> CGSize {
    let pair = PairView()
    pair.title.text = "Messages"
    pair.subtitle.text = "Three unread"
    return sizes.size(
        of: pair,
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
    )
}

enum BadgeLayout {}

struct BadgeStyle: Hashable {
    let fontSize: CGFloat
}

@MainActor
final class BadgeMeasurer {
    private let cache = LayoutCache<BadgeLayout, String, BadgeStyle, CGSize>(capacity: 32)

    func size(of text: String, toFit fittingSize: CGSize, style: BadgeStyle) throws -> CGSize {
        let proposal = try FittingProposal(fitting: fittingSize)
        return cache.value(for: text, proposal: proposal, context: style) {
            text,
            proposal,
            style in
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: style.fontSize)
            label.numberOfLines = 1
            label.textAlignment = .left
            label.semanticContentAttribute = .forceLeftToRight
            return label.sizeThatFits(proposal.fittingSize)
        }
    }
}

@MainActor
func measureBadge(using measurer: BadgeMeasurer) throws -> CGSize {
    try measurer.size(
        of: "Unread",
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude),
        style: BadgeStyle(fontSize: 17)
    )
}

@MainActor
func documentationMeasurements() throws {
    // In an app, keep these owners for subsequent requests.
    let textSizes = makeTextSizes()
    let pairSizes = makePairSizes(titleSizes: textSizes)
    let badges = BadgeMeasurer()
    _ = measureText(using: textSizes)
    _ = measurePair(using: pairSizes)
    _ = try measureBadge(using: badges)
    _ = try measureBadge(using: badges)
}
