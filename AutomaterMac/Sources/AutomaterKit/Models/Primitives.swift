import Foundation

/// Mouse button selector, matching the JSON schema's "left"/"right"/"middle".
public enum MouseButton: String, Codable, Sendable, CaseIterable {
    case left, right, middle
}

/// Single / double / triple click semantics.
public enum ClickKind: String, Codable, Sendable, CaseIterable {
    case single, double, triple

    /// Physical press-release cycles a kind expands to.
    public var presses: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        }
    }
}

/// Coordinate space for a step or fixed point.
public enum CoordSpace: String, Codable, Sendable {
    case screen, window
}
