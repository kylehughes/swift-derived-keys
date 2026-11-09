# Measuring a text component

`DerivedKeysUIExample` includes `TextComponentMeasurer`, which measures a vertical stack of plain text and an optional expansion button. It is a non-product example target inside this repository that demonstrates how to compose child `RequestKey` values explicitly rather than using `SizeCache` key paths.

For ordinary view sizing in an app, start with the [size-cache guide](Size-Caches.md). For explicit-input layout caching with `LayoutCache` from `DerivedKeysUI`, see the [UIKit guide](UI-Measurement.md). The generic `DerivedKeys` library has no UIKit dependency; UIKit declarations and tests in the example target are gated with `#if canImport(UIKit)`.

```swift
import DerivedKeysUI
import DerivedKeysUIExample

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

Retain one `TextComponentMeasurer` across requests so its internal caches stay populated. Capture a coherent input snapshot inside the code that owns model mutations; the main-actor measurement API runs synchronously without suspending and uses that same snapshot for both key formation and calculation. It never retains a model, callback, provider closure, or view.

## Inputs consumed by this algorithm

The measurer builds three distinct keys—each with its own nominal `Operation` type and independently bounded LRU cache:

- **Text child key:** captures the rendered plain-text string, a concrete font name and point size (`MeasurementFont` resolves the font name on the main actor, so resolve Dynamic Type to a concrete point size before constructing it), maximum line count, wrapping or truncation mode, effective inner width and height, and display scale. Measurement configures a `UILabel` with forced left-to-right semantic direction and calls UIKit's plain-text `sizeThatFits(_:)` in the current process-local font environment. The example intentionally excludes arbitrary font descriptors, attributed strings, paragraph styles, attachments, images, fitting priorities, and locale-dependent formatting.
- **Button child key:** captures the single-line title (which truncates at the tail), font, button style, effective inner bounds, and display scale. Here `style` is a layout input rather than a paint style: `.plain` adds no content insets, whereas `.padded` adds 12 points horizontally and 6 points vertically on each side. Measurement does not read `UIButton`'s ambient configuration or appearance state.
- **Parent key:** composes the complete text child key, the optional button child key, outer padding, visible-button spacing, the outer fitting proposal, and the `MeasurementContext`. Parent keys embed the full child dependency keys rather than child sizes or integer hashes. When the button is `nil`, the parent key has no button child key and normalizes `spacing` to zero, so hidden-button properties (title, style, font, or action callbacks) cannot invalidate the parent entry.

## Layout policy

Both children are measured against the outer proposal inset by `padding`. The parent stacks their independently measured sizes vertically, adds `padding` and visible-button `spacing`, rounds dimensions upward to the display pixel grid, and clamps to the outer proposed width and height. Because this example does not partition remaining height between the text and button, a finite height bound can clip the stacked total.

Child measurements also round upward to the pixel grid and clamp to their inner proposal bounds. When a finite proposal bound is not pixel-aligned, clamping wins over upward pixel rounding. If multiplying a finite dimension by the display scale would overflow, that dimension is left unrounded rather than overflowing.

## Validation and reuse

All inputs are validated at construction time and stored in private immutable fields with no `Codable` or raw-value bypass:

- **Proposals:** `FittingDimension(points:)` requires a finite, nonnegative value and throws `FittingProposalError.invalidDimension` for NaN, infinity, or negative numbers. Use `.unconstrained` for an unbounded axis; the UIKit adapter converts `.unconstrained` to `CGFloat.greatestFiniteMagnitude` only when calling `sizeThatFits(_:)` and never rounds proposal bounds. When bridging from a `CGSize`, `FittingProposal(fitting:)` treats positive infinity the same as `CGFloat.greatestFiniteMagnitude`.
- **Geometry and typography:** Insets and spacing must be finite and nonnegative, and the horizontal (`left + right`) and vertical (`top + bottom`) inset sums must also be finite. Display scale must be finite and positive, named fonts must resolve on the system at a finite positive point size, and line count must be nonnegative.

Project actual content into the input structs even when an entity ID has not changed. Paint-only colors, analytics identifiers, unrelated URLs, action handlers, and view identity are omitted because the sizing calculation never reads them. Two views with equal snapshots share cached sizes, a reused view with new content supplies a new snapshot, and changing inputs from A to B and back to A reproduces the original key and hits its entry if still retained.

Updating a dependency, requesting a size, scheduling layout, and publishing that size to a container remain separate application steps; these types never observe models or trigger layout automatically. The calculation counters on `TextComponentMeasurer` exist to verify cache reuse in tests and are not part of any key.
