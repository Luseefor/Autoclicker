import CoreGraphics

/// Verified against CoreGraphics' CGEventTypes.h — the Swift overlay does not
/// surface these fields, and raw values are stable API contract numbers.
extension CGEventField {
    /// `kCGMouseEventClickState` — 1 single, 2 double, 3 triple.
    static let clickState = CGEventField(rawValue: 1)!
    /// `kCGMouseEventButtonNumber`.
    static let buttonNumber = CGEventField(rawValue: 3)!
    /// Routes pid-posted events into a specific (possibly unfocused) window.
    static let windowUnderMousePointer = CGEventField(rawValue: 91)!
    /// Variant that also matches windows able to handle this event class.
    static let windowUnderMousePointerHandler = CGEventField(rawValue: 92)!
}
