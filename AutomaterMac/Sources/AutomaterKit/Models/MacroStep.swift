import Foundation

/// One recorded/authored automation step.
///
/// JSON keys intentionally mirror the Python app's schema (snake_case) so
/// existing macro files stay loadable across both implementations.
public struct MacroStep: Codable, Equatable, Sendable {
    public var type: String
    public var x: Int?
    public var y: Int?
    public var button: String?
    public var key: String?
    public var text: String?
    public var delayMs: Int
    public var clicks: Int
    public var dx: Int?
    public var dy: Int?

    // Localization
    public var coordSpace: String
    public var appBundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var windowId: Int?
    public var localX: Double?
    public var localY: Double?

    // Drag / hold endpoints
    public var endX: Int?
    public var endY: Int?
    public var endLocalX: Double?
    public var endLocalY: Double?
    public var holdMs: Int

    public var clickKind: String
    public var timeoutMs: Int

    public init(
        type: String,
        x: Int? = nil,
        y: Int? = nil,
        button: String? = nil,
        key: String? = nil,
        text: String? = nil,
        delayMs: Int = 0,
        clicks: Int = 1,
        dx: Int? = nil,
        dy: Int? = nil,
        coordSpace: String = "screen",
        appBundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        windowId: Int? = nil,
        localX: Double? = nil,
        localY: Double? = nil,
        endX: Int? = nil,
        endY: Int? = nil,
        endLocalX: Double? = nil,
        endLocalY: Double? = nil,
        holdMs: Int = 0,
        clickKind: String = "single",
        timeoutMs: Int = 10_000
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.button = button
        self.key = key
        self.text = text
        self.delayMs = delayMs
        self.clicks = clicks
        self.dx = dx
        self.dy = dy
        self.coordSpace = coordSpace
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.localX = localX
        self.localY = localY
        self.endX = endX
        self.endY = endY
        self.endLocalX = endLocalX
        self.endLocalY = endLocalY
        self.holdMs = holdMs
        self.clickKind = clickKind
        self.timeoutMs = timeoutMs
    }

    enum CodingKeys: String, CodingKey {
        case type, x, y, button, key, text, clicks, dx, dy
        case delayMs = "delay_ms"
        case coordSpace = "coord_space"
        case appBundleId = "app_bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case windowId = "window_id"
        case localX = "local_x"
        case localY = "local_y"
        case endX = "end_x"
        case endY = "end_y"
        case endLocalX = "end_local_x"
        case endLocalY = "end_local_y"
        case holdMs = "hold_ms"
        case clickKind = "click_kind"
        case timeoutMs = "timeout_ms"
    }

    /// Lenient decode matching Python's `MacroStep.from_dict`, which fills
    /// dataclass defaults for any absent key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.x = try c.decodeIfPresent(Int.self, forKey: .x)
        self.y = try c.decodeIfPresent(Int.self, forKey: .y)
        self.button = try c.decodeIfPresent(String.self, forKey: .button)
        self.key = try c.decodeIfPresent(String.self, forKey: .key)
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
        self.clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 1
        self.dx = try c.decodeIfPresent(Int.self, forKey: .dx)
        self.dy = try c.decodeIfPresent(Int.self, forKey: .dy)
        self.coordSpace = try c.decodeIfPresent(String.self, forKey: .coordSpace) ?? "screen"
        self.appBundleId = try c.decodeIfPresent(String.self, forKey: .appBundleId)
        self.appName = try c.decodeIfPresent(String.self, forKey: .appName)
        self.windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        self.windowId = try c.decodeIfPresent(Int.self, forKey: .windowId)
        self.localX = try c.decodeIfPresent(Double.self, forKey: .localX)
        self.localY = try c.decodeIfPresent(Double.self, forKey: .localY)
        self.endX = try c.decodeIfPresent(Int.self, forKey: .endX)
        self.endY = try c.decodeIfPresent(Int.self, forKey: .endY)
        self.endLocalX = try c.decodeIfPresent(Double.self, forKey: .endLocalX)
        self.endLocalY = try c.decodeIfPresent(Double.self, forKey: .endLocalY)
        self.holdMs = try c.decodeIfPresent(Int.self, forKey: .holdMs) ?? 0
        self.clickKind = try c.decodeIfPresent(String.self, forKey: .clickKind) ?? "single"
        self.timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 10_000
    }
}
