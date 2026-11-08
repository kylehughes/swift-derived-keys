#if canImport(UIKit)
import DerivedKeys
import DerivedKeysUIKit
import UIKit

/// A resolved named font, rather than a view or an ambient Dynamic Type dependency.
public struct MeasurementFont: Hashable, Sendable {
    private let storedName: String
    private let storedPointSize: Double

    /// The resolved PostScript font name.
    public var name: String {
        storedName
    }
    /// The resolved size in points.
    public var pointSize: Double {
        storedPointSize
    }

    /// Resolves a named font on the main actor.
    ///
    /// Unsupported names and invalid sizes throw.
    /// Resolve Dynamic Type to a concrete size before calling this initializer.
    @MainActor
    public init(name: String, pointSize: Double) throws {
        guard pointSize.isFinite, pointSize > 0,
            let font = UIFont(name: name, size: CGFloat(pointSize))
        else {
            throw MeasurementInputError.invalidFont
        }
        storedName = font.fontName
        storedPointSize = Double(font.pointSize)
    }

    @MainActor
    fileprivate var uiFont: UIFont {
        // The same named font was resolved at construction; fonts are process-local resources.
        guard let font = UIFont(name: name, size: CGFloat(pointSize)) else {
            preconditionFailure("A previously resolved font must remain available.")
        }
        return font
    }
}

/// Supported plain-text wrapping and truncation policies.
public enum MeasurementLineBreak: Hashable, Sendable {
    /// Wraps text at word boundaries.
    case wordWrapping
    /// Truncates the beginning of text.
    case truncatingHead
    /// Truncates the middle of text.
    case truncatingMiddle
    /// Truncates the end of text.
    case truncatingTail

    fileprivate var uiMode: NSLineBreakMode {
        switch self {
        case .wordWrapping: .byWordWrapping
        case .truncatingHead: .byTruncatingHead
        case .truncatingMiddle: .byTruncatingMiddle
        case .truncatingTail: .byTruncatingTail
        }
    }
}

/// The complete metric-affecting configuration read by the text calculation.
public struct TextMeasurementInput: Hashable, Sendable {
    /// The rendered plain-text content.
    public let text: String
    /// The resolved font used to measure the text.
    public let font: MeasurementFont
    /// The wrapping or truncation policy.
    public let lineBreak: MeasurementLineBreak
    private let storedNumberOfLines: Int

    /// Zero means unlimited lines, matching UILabel.
    public var numberOfLines: Int {
        storedNumberOfLines
    }

    /// Creates text inputs with a nonnegative line count.
    public init(
        text: String,
        font: MeasurementFont,
        numberOfLines: Int = 0,
        lineBreak: MeasurementLineBreak = .wordWrapping
    ) throws {
        guard numberOfLines >= 0 else {
            throw MeasurementInputError.invalidLineCount
        }
        self.text = text
        self.font = font
        self.lineBreak = lineBreak
        storedNumberOfLines = numberOfLines
    }
}

/// Styles whose fixed content insets are consumed by this example's button sizing.
public enum MeasurementButtonStyle: Hashable, Sendable {
    /// Adds no content insets.
    case plain
    /// Adds twelve horizontal and six vertical points on each side.
    case padded

    fileprivate var horizontalInset: Double {
        self == .plain ? 0 : 12
    }
    fileprivate var verticalInset: Double {
        self == .plain ? 0 : 6
    }
}

/// A single-line plain-text expansion button; images and attributed titles are unsupported.
public struct ButtonMeasurementInput: Hashable, Sendable {
    /// The rendered plain-text title.
    public let title: String
    /// The resolved font used to measure the title.
    public let font: MeasurementFont
    /// The fixed content-inset policy.
    public let style: MeasurementButtonStyle

    /// Creates the inputs for a single-line expansion button.
    public init(title: String, font: MeasurementFont, style: MeasurementButtonStyle = .plain) {
        self.title = title
        self.font = font
        self.style = style
    }
}

/// An immutable component snapshot.
///
/// A missing button represents hidden button content.
public struct TextComponentInput: Hashable, Sendable {
    /// The text child's measurement inputs.
    public let text: TextMeasurementInput
    /// The visible button's inputs, or `nil` for a hidden button.
    public let button: ButtonMeasurementInput?
    /// The insets surrounding the child stack.
    public let padding: MeasurementInsets
    private let storedSpacing: Double

    /// The gap between text and a visible button, in points.
    public var spacing: Double {
        storedSpacing
    }

    /// Creates a component snapshot with finite nonnegative spacing.
    public init(
        text: TextMeasurementInput,
        button: ButtonMeasurementInput? = nil,
        padding: MeasurementInsets,
        spacing: Double = 0
    ) throws {
        guard spacing.isFinite, spacing >= 0 else {
            throw MeasurementInputError.invalidDimension
        }
        self.text = text
        self.button = button
        self.padding = padding
        storedSpacing = spacing
    }
}

/// The nominal namespace for text measurement requests.
public enum TextMeasurementOperation {}
/// The nominal namespace for button measurement requests.
public enum ButtonMeasurementOperation {}
/// The nominal namespace for component measurement requests.
public enum ComponentMeasurementOperation {}

/// Text dependencies include the effective inner bounds automatically.
public struct TextMeasurementDependencies: Hashable, Sendable {
    /// The text configuration captured for this request.
    public let input: TextMeasurementInput
    /// The effective bounds passed to text sizing.
    public let proposal: FittingProposal
}

/// Button dependencies include the effective inner bounds automatically.
public struct ButtonMeasurementDependencies: Hashable, Sendable {
    /// The button configuration captured for this request.
    public let input: ButtonMeasurementInput
    /// The effective bounds available to the button.
    public let proposal: FittingProposal
}

/// A text request scoped by operation, dependencies, and measurement context.
public typealias TextMeasurementKey = RequestKey<
    TextMeasurementOperation, TextMeasurementDependencies, MeasurementContext
>
/// A button request scoped by operation, dependencies, and measurement context.
public typealias ButtonMeasurementKey = RequestKey<
    ButtonMeasurementOperation, ButtonMeasurementDependencies, MeasurementContext
>

/// Parent dependencies preserve the complete child keys, including optional presence.
public struct ComponentMeasurementDependencies: Hashable, Sendable {
    /// The complete text child request key.
    public let text: TextMeasurementKey
    /// The complete visible button request key, or `nil` when hidden.
    public let button: ButtonMeasurementKey?
    /// The insets surrounding the child stack.
    public let padding: MeasurementInsets
    /// The child gap, normalized to zero when the button is hidden.
    public let spacing: Double
    /// The outer bounds used to clamp the stack's size.
    public let proposal: FittingProposal
}

/// A component request that preserves its complete child dependencies and context.
public typealias ComponentMeasurementKey = RequestKey<
    ComponentMeasurementOperation, ComponentMeasurementDependencies, MeasurementContext
>

/// Main-actor sizing with separate bounded caches for children and their parent.
///
/// Cache entries own plain snapshots and sizes, never UIViews or callbacks. The adapter
/// measures a vertical text/button stack and clamps its result to the supplied bounds.
@MainActor
public final class TextComponentMeasurer {
    private var textCache: MemoizationCache<TextMeasurementKey, CGSize>
    private var buttonCache: MemoizationCache<ButtonMeasurementKey, CGSize>
    private var componentCache: MemoizationCache<ComponentMeasurementKey, CGSize>

    /// The number of text calculations performed on cache misses.
    public private(set) var textCalculationCount = 0
    /// The number of button calculations performed on cache misses.
    public private(set) var buttonCalculationCount = 0
    /// The number of component calculations performed on cache misses.
    public private(set) var componentCalculationCount = 0

    /// Creates independently bounded caches with the same explicit nonnegative capacity.
    public init(capacity: Int) {
        textCache = MemoizationCache(capacity: capacity)
        buttonCache = MemoizationCache(capacity: capacity)
        componentCache = MemoizationCache(capacity: capacity)
    }

    /// Captures the exact child and parent proposals used by `size(for:proposal:context:)`.
    public func key(
        for input: TextComponentInput,
        proposal: FittingProposal,
        context: MeasurementContext
    ) -> ComponentMeasurementKey {
        let inner = FittingProposal(
            width: Self.subtracting(input.padding.left + input.padding.right, from: proposal.width),
            height: Self.subtracting(input.padding.top + input.padding.bottom, from: proposal.height)
        )
        let text = TextMeasurementKey(
            dependencies: TextMeasurementDependencies(input: input.text, proposal: inner),
            context: context
        )
        let button = input.button.map {
            ButtonMeasurementKey(
                dependencies: ButtonMeasurementDependencies(input: $0, proposal: inner),
                context: context
            )
        }
        return ComponentMeasurementKey(
            dependencies: ComponentMeasurementDependencies(
                text: text,
                button: button,
                padding: input.padding,
                spacing: button == nil ? 0 : input.spacing,
                proposal: proposal
            ),
            context: context
        )
    }

    /// Returns a component size using the captured request inputs.
    ///
    /// Child cache lookups precede the component lookup; each cache calculates only on a miss.
    public func size(
        for input: TextComponentInput,
        proposal: FittingProposal,
        context: MeasurementContext
    ) -> CGSize {
        let request = key(for: input, proposal: proposal, context: context)
        let dependencies = request.dependencies
        var calculatedText = false
        let textSize = textCache.value(for: dependencies.text) {
            calculatedText = true
            return Self.measureText(dependencies.text.dependencies, context: context)
        }
        if calculatedText {
            textCalculationCount += 1
        }
        var buttonSize = CGSize.zero
        if let button = dependencies.button {
            var calculatedButton = false
            buttonSize = buttonCache.value(for: button) {
                calculatedButton = true
                return Self.measureButton(button.dependencies, context: context)
            }
            if calculatedButton {
                buttonCalculationCount += 1
            }
        }
        var calculatedComponent = false
        let size = componentCache.value(for: request) {
            calculatedComponent = true
            return Self.roundAndClamp(
                CGSize(
                    width: max(textSize.width, buttonSize.width) + CGFloat(input.padding.left + input.padding.right),
                    height: textSize.height + buttonSize.height
                        + CGFloat(dependencies.spacing + input.padding.top + input.padding.bottom)
                ),
                proposal: proposal,
                context: context
            )
        }
        if calculatedComponent {
            componentCalculationCount += 1
        }
        return size
    }

    private static func measureText(
        _ dependencies: TextMeasurementDependencies,
        context: MeasurementContext
    ) -> CGSize {
        let label = UILabel()
        label.text = dependencies.input.text
        label.font = dependencies.input.font.uiFont
        label.numberOfLines = dependencies.input.numberOfLines
        label.lineBreakMode = dependencies.input.lineBreak.uiMode
        label.semanticContentAttribute = .forceLeftToRight
        return roundAndClamp(
            label.sizeThatFits(dependencies.proposal.fittingSize),
            proposal: dependencies.proposal,
            context: context
        )
    }

    private static func measureButton(
        _ dependencies: ButtonMeasurementDependencies,
        context: MeasurementContext
    ) -> CGSize {
        let input = dependencies.input
        let horizontal = input.style.horizontalInset * 2
        let vertical = input.style.verticalInset * 2
        let contentProposal = FittingProposal(
            width: subtracting(horizontal, from: dependencies.proposal.width),
            height: subtracting(vertical, from: dependencies.proposal.height)
        )
        let label = UILabel()
        label.text = input.title
        label.font = input.font.uiFont
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.semanticContentAttribute = .forceLeftToRight
        let size = label.sizeThatFits(contentProposal.fittingSize)
        return roundAndClamp(
            CGSize(width: size.width + CGFloat(horizontal), height: size.height + CGFloat(vertical)),
            proposal: dependencies.proposal,
            context: context
        )
    }

    private static func subtracting(_ points: Double, from dimension: FittingDimension) -> FittingDimension {
        guard let limit = dimension.limit else { return .unconstrained }
        // Both operands are validated finite nonnegative values; subtraction is clamped at zero.
        return try! FittingDimension(points: max(0, limit - points))
    }

    private static func roundAndClamp(
        _ size: CGSize,
        proposal: FittingProposal,
        context: MeasurementContext
    ) -> CGSize {
        func dimension(_ value: CGFloat, limit: Double?) -> CGFloat {
            let points = Double(value)
            // Avoid overflow in the product for extreme, but valid, finite inputs.
            let scaled = points * context.displayScale
            let rounded = scaled.isFinite ? scaled.rounded(.up) / context.displayScale : points
            return CGFloat(min(max(0, rounded), limit ?? .greatestFiniteMagnitude))
        }
        return CGSize(
            width: dimension(size.width, limit: proposal.width.limit),
            height: dimension(size.height, limit: proposal.height.limit)
        )
    }
}
#endif
