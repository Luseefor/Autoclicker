import CoreGraphics
import Foundation

/// Posts synthetic CG events — globally (HID tap) or targeted at one process
/// and window, which is what makes background clicking work without moving
/// the physical pointer.
public struct EventPoster: Sendable {

    public init() {}

    // MARK: - Mouse

    /// Posts a two-axis scroll in line units (schema dx = horizontal,
    /// dy = vertical, matching the Python engine's `_scroll`).
    public func scroll(
        dx: Int,
        dy: Int,
        pid: pid_t? = nil,
        windowNumber: Int? = nil
    ) {
        guard dx != 0 || dy != 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(clamping: dy),
            wheel2: Int32(clamping: dx),
            wheel3: 0
        ) else { return }
        if let windowNumber {
            event.setIntegerValueField(
                .windowUnderMousePointer, value: Int64(windowNumber)
            )
            event.setIntegerValueField(
                .windowUnderMousePointerHandler, value: Int64(windowNumber)
            )
        }
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    public func postMouseEvent(
        _ type: CGEventType,
        x: Double,
        y: Double,
        button: MouseButton = .left,
        pid: pid_t? = nil,
        clickState: Int = 1,
        windowNumber: Int? = nil
    ) {
        let source = CGEventSource(
            stateID: pid != nil ? .privateState : .combinedSessionState
        )
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: x, y: y),
            mouseButton: button.cgButton
        ) else { return }

        event.location = CGPoint(x: x, y: y)
        event.setIntegerValueField(.clickState, value: Int64(clickState))
        if let windowNumber {
            event.setIntegerValueField(
                .windowUnderMousePointer, value: Int64(windowNumber)
            )
            event.setIntegerValueField(
                .windowUnderMousePointerHandler, value: Int64(windowNumber)
            )
        }
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    public func moveCursor(
        x: Double, y: Double,
        pid: pid_t? = nil,
        windowNumber: Int? = nil
    ) {
        postMouseEvent(
            .mouseMoved, x: x, y: y, button: .left,
            pid: pid, clickState: 0, windowNumber: windowNumber
        )
    }

    /// Full press/release series for a click kind at one point.
    public func click(
        x: Double, y: Double,
        button: MouseButton = .left,
        kind: ClickKind = .single,
        pid: pid_t? = nil,
        windowNumber: Int? = nil
    ) {
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .right:
            downType = .rightMouseDown; upType = .rightMouseUp
        case .middle:
            downType = .otherMouseDown; upType = .otherMouseUp
        case .left:
            downType = .leftMouseDown; upType = .leftMouseUp
        }

        for press in 1...kind.presses {
            postMouseEvent(downType, x: x, y: y, button: button,
                           pid: pid, clickState: press, windowNumber: windowNumber)
            Thread.sleep(forTimeInterval: 0.012)
            postMouseEvent(upType, x: x, y: y, button: button,
                           pid: pid, clickState: press, windowNumber: windowNumber)
            if press < kind.presses {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    /// Physically relocates the system pointer (foreground delivery only).
    public func warpCursor(x: Double, y: Double) {
        CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Foreground click: warp first so the HID click can't land stale.
    public func foregroundClick(
        x: Double, y: Double,
        button: MouseButton = .left,
        kind: ClickKind = .single
    ) {
        warpCursor(x: x, y: y)
        Thread.sleep(forTimeInterval: 0.02)
        moveCursor(x: x, y: y)
        click(x: x, y: y, button: button, kind: kind)
    }

    /// Background click straight into one process+window; pointer untouched.
    public func backgroundClick(
        x: Double, y: Double,
        pid: pid_t,
        childPIDs: [pid_t] = [],
        windowNumber: Int? = nil,
        button: MouseButton = .left,
        kind: ClickKind = .single
    ) {
        var targets = [pid]
        for child in childPIDs where !targets.contains(child) {
            targets.append(child)
        }
        for target in targets {
            moveCursor(x: x, y: y, pid: target, windowNumber: windowNumber)
            click(x: x, y: y, button: button, kind: kind,
                  pid: target, windowNumber: windowNumber)
        }
    }

    /// AXPress-based background click: no synthetic events at all.
    /// Returns true when at least one press actually landed on an element.
    @discardableResult
    public func axClick(
        x: Double, y: Double,
        pid: pid_t,
        button: MouseButton = .left,
        kind: ClickKind = .single
    ) -> Bool {
        var delivered = false
        for _ in 0..<kind.presses {
            if AXBridge.pressAt(appPID: pid, x: x, y: y) {
                delivered = true
            }
            if kind.presses > 1 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return delivered
    }

    // MARK: - Keyboard

    /// Posts a key or chord ("cmd+c") to a process. Returns false when any
    /// part has no virtual keycode so callers can fall back.
    @discardableResult
    public func keyCombo(
        _ combo: String,
        pid: pid_t
    ) -> Bool {
        let parts = combo.split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }

        var modCodes: [UInt16] = []
        var tail: UInt16?
        for part in parts {
            guard let code = KeyCodeMap.keycode(for: part) else { return false }
            if KeyCodeMap.isModifier(name: part) {
                modCodes.append(code)
            } else {
                tail = code
            }
        }
        guard let tail else { return false }

        let flags: CGEventFlags = modCodes.reduce(into: CGEventFlags()) { acc, code in
            acc.insert(Self.flag(forVirtual: code))
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        func post(_ keycode: UInt16, _ down: Bool) {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keycode,
                keyDown: down
            ) else { return }
            if !flags.isEmpty { event.flags = flags }
            event.postToPid(pid)
        }

        for code in modCodes { post(code, true) }
        post(tail, true)
        Thread.sleep(forTimeInterval: 0.008)
        post(tail, false)
        for code in modCodes.reversed() { post(code, false) }
        return true
    }

    private static func flag(forVirtual code: UInt16) -> CGEventFlags {
        switch code {
        case 55, 54: return .maskCommand
        case 59, 62: return .maskControl
        case 58, 61: return .maskAlternate
        case 56, 60: return .maskShift
        default: return []
        }
    }

    // MARK: - Cursor query

    public static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}

extension MouseButton {
    /// CG counterpart for synthetic event construction.
    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }
}
