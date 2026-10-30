# Measuring a text component

`DerivedKeysUIExample` is a non-product example target in this repository. Its UIKit adapter measures a
vertical stack of plain text and an optional expansion button. The generic
`DerivedKeys` library has no UIKit dependency. The supported fitting and cache API lives in `DerivedKeysUIKit`. UIKit declarations and tests use `#if canImport(UIKit)`.

This example runs inside the repository. To integrate your own view in an app, start with the [UIKit guide](UI-Measurement.md) and the supported `DerivedKeysUIKit` product. This text/button example demonstrates explicit composition of child dependency keys; the [size-cache guide](Size-Caches.md) covers the key-path sizing facade.

```swift
import DerivedKeysUIExample
import DerivedKeysUIKit

@MainActor
func example() throws {
    let font = try MeasurementFont(name: "Helvetica", pointSize: 17)
    let text = try TextMeasurementInput(
        text: "A paragraph that can expand.", font: font,
        numberOfLines: 3, lineBreak: .truncatingTail
    )
    let input = try TextComponentInput(
        text: text,
        button: ButtonMeasurementInput(title: "Show more", font: font, style: .padded),
        padding: MeasurementInsets(top: 8, left: 12, bottom: 8, right: 12),
        spacing: 6
    )
    let proposal = try FittingProposal(width: FittingDimension(points: 240))
    let context = try MeasurementContext(displayScale: 2)
    let measurer = TextComponentMeasurer(capacity: 64)
    let size = measurer.size(for: input, proposal: proposal, context: context)
    // Publish size to the container using the application's normal layout API.
    _ = size
}
```

Keep the measurer alive across requests to retain its caches. Capture a coherent
snapshot in the code that owns model mutation. The main-actor API does not suspend
and uses the same snapshot for both key formation and calculation. It does not
retain a model, callback, provider, or view.

## Inputs consumed by this algorithm

The text child key contains rendered plain text, a concrete named font and point
size, line count, wrapping/truncation policy, effective inner width and height,
and display scale. `MeasurementFont` resolves the name on the main actor; resolve
Dynamic Type to a concrete point size before constructing it. The example does
not accept arbitrary font descriptors, attributed text, paragraph styles,
attachments, images, or fitting priorities. It does not perform locale-dependent
formatting. Labels use forced left-to-right semantic direction and UIKit's
plain-text shaping and `sizeThatFits`; the font environment is process-local.

The button child key contains its title, font, style, effective inner bounds, and
display scale. Its single-line title truncates at the tail. `plain` adds no
content insets; `padded` adds 12 points on each horizontal side and 6 on each
vertical side. Here, style controls these measurements; it does not use UIButton's
ambient configuration or a paint style.

The parent key contains the complete text child key, the optional button child
key, padding, visible-button spacing, outer proposal, and context. Hidden buttons
have no child key, so their title, style, font, and callback cannot invalidate the
parent. Spacing is normalized to zero when no button exists. Parent keys compose
child dependency keys, rather than sizes or hashes. All three operations have
separate nominal namespaces and independently bounded LRU caches.

## Layout policy

Both children fit within the outer proposal minus padding. The parent stacks
their independently measured sizes, adds visible-button spacing and padding,
rounds upward to the display pixel grid, and clamps to the outer width and height.
A bounded height can therefore clip the stack; this example does not allocate
remaining height between the children. Child results also round and clamp. A
non-pixel-aligned bound wins over pixel rounding. Extreme finite products avoid
overflow in rounding by leaving that dimension unrounded.

## Validation and reuse

`FittingDimension(points:)` accepts finite nonnegative dimensions and rejects
NaN, infinity, and negatives with `FittingProposalError.invalidDimension`.
Use `.unconstrained` explicitly; the UIKit adapter translates it to
`CGFloat.greatestFiniteMagnitude` only when calling `sizeThatFits`. It never
silently interprets raw infinity as a valid bound. No proposal quantization is
performed. Insets and spacing are finite and nonnegative; inset totals must
remain finite. Display scale must be finite and positive, named fonts must resolve
at a finite positive size, and line count must be nonnegative. Validation uses
immutable private storage with no decoding or raw-value construction path.

Project actual content into the key, even when an entity ID stays unchanged.
Paint-only colors, analytics identifiers, unrelated URLs, actions, and view
identity are excluded because the sizing algorithm does not read them. Two
different views with equal snapshots can share sizes. A reused view with changed
content supplies a new snapshot. A→B→A inputs recover the original key and may
reuse its retained entry.

Changing a dependency, asking for a size, scheduling layout, and publishing that
size are separate application actions. These keys do not trigger layout or
observe model changes. The calculation counters demonstrate reuse; they are
diagnostics rather than dependencies.
