#if canImport(UIKit)
import DerivedKeysUIKit
import UIKit

/// A frame-layout example that caches both its fitted size and its label frame.
///
/// Typography, padding, wrapping, and left-to-right direction are fixed by this example.
/// Only text and available width affect layout; color is a paint-only property. A parent
/// should assign the width returned by `sizeThatFits(_:)` before laying out the view.
@MainActor
public final class LabelView: UIView {
    /// The operation namespace separating this layout algorithm from other calculations.
    public enum Operation {}

    /// The empty context for an algorithm with fixed typography and direction.
    public struct LayoutContext: Hashable {
        /// Creates the context for this fixed layout policy.
        public init() {}
    }

    /// An immutable fitted size and child frame, with the frame relative to a zero origin.
    public struct Layout {
        /// The complete view's fitted size in points.
        public let size: CGSize
        /// The label frame before adding the view's bounds origin.
        public let labelFrame: CGRect
    }

    /// A cache that may be shared by views using this exact layout algorithm.
    public typealias Cache = LayoutCache<Operation, String, LayoutContext, Layout>

    private static let padding: CGFloat = 12

    private let cache: Cache
    private let label = UILabel()

    /// The number of cache misses calculated by this view, excluding shared-cache hits.
    public private(set) var calculationCount = 0

    /// The displayed plain text; changing it schedules layout without discarding old results.
    public var text: String {
        didSet {
            label.text = text
            setNeedsLayout()
        }
    }

    /// The displayed text color, which does not affect the cached layout.
    public var textColor: UIColor {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    /// Creates a view with a retained bounded cache, or an explicitly shared cache.
    public init(text: String = "", cache: Cache = Cache(capacity: 32)) {
        self.cache = cache
        self.text = text
        super.init(frame: .zero)
        configureLabel()
    }

    /// Creates a decoded view with an empty text value and its own bounded cache.
    public required init?(coder: NSCoder) {
        cache = Cache(capacity: 32)
        text = ""
        super.init(coder: coder)
        configureLabel()
    }

    /// Fits the text to the supplied width, ignoring the supplied height.
    ///
    /// A finite nonnegative width is filled exactly. The greatest-finite-magnitude
    /// sentinel requests natural width. Invalid widths return zero without caching.
    /// Widths smaller than the padding leave a zero-width label and padding-only height.
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        layout(forWidth: size.width)?.size ?? .zero
    }

    /// Applies the same complete layout used by fitting, translated to the bounds origin.
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout = layout(forWidth: bounds.width) else {
            label.frame = .zero
            return
        }
        label.frame = layout.labelFrame.offsetBy(dx: bounds.minX, dy: bounds.minY)
    }

    private func configureLabel() {
        Self.configure(label, text: text)
        addSubview(label)
    }

    private static func configure(_ label: UILabel, text: String) {
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .left
        label.semanticContentAttribute = .forceLeftToRight
    }

    private func layout(forWidth width: CGFloat) -> Layout? {
        guard
            let proposal = try? DerivedKeysUIKit.FittingProposal(
                fitting: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            )
        else {
            return nil
        }
        var calculated = false
        let layout = cache.value(for: text, proposal: proposal, context: LayoutContext()) { text, proposal, _ in
            calculated = true
            return Self.calculate(text: text, proposal: proposal)
        }
        if calculated {
            calculationCount += 1
        }
        return layout
    }

    private static func calculate(text: String, proposal: DerivedKeysUIKit.FittingProposal) -> Layout {
        let width = proposal.fittingSize.width
        let isUnconstrained = width == CGFloat.greatestFiniteMagnitude
        let innerWidth = isUnconstrained ? width : max(0, width - padding * 2)
        // Measure a fresh label from the captured request, never the displayed label.
        let measuringLabel = UILabel()
        configure(measuringLabel, text: text)
        let measured =
            innerWidth > 0
            ? measuringLabel.sizeThatFits(CGSize(width: innerWidth, height: CGFloat.greatestFiniteMagnitude))
            : .zero
        let labelHeight = ceil(measured.height)
        let outerWidth = isUnconstrained ? ceil(measured.width) + padding * 2 : width
        let labelWidth = max(0, outerWidth - padding * 2)
        return Layout(
            size: CGSize(width: outerWidth, height: labelHeight + padding * 2),
            labelFrame: CGRect(
                x: min(padding, outerWidth / 2),
                y: padding,
                width: labelWidth,
                height: labelHeight
            )
        )
    }
}
#endif
