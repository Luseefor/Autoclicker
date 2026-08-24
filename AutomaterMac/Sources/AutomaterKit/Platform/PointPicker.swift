import CoreGraphics
import AppKit
import Foundation

/// Click-to-capture mode: while active, every left/right click's position is
/// reported and swallowed (doesn't reach other apps). Clicks on this app's
/// own windows pass through untouched (so "Finish Picking" finishes).
/// Escape ends the pick.
public final class PointPicker {
    public var onPoint: ((CGPoint) -> Void)?
    /// `finished` is true for explicit completion (button/Esc), false when
    /// the tap couldn't be created at all (missing permission).
    public var onFinish: ((_ finished: Bool) -> Void)?
    public private(set) var count = 0
    /// When true, the first captured point ends the pick (fixed-point grab).
    public var singleShot = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var active: Bool { tap != nil }

    private static let escapeKeyCode: UInt16 = 53

    public init() {}

    public func start() {
        guard tap == nil else { return }
        count = 0

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let picker = Unmanaged<PointPicker>.fromOpaque(refcon).takeUnretainedValue()
            return picker.handle(type: type, event: event)
        }

        func maskBit(_ t: CGEventType) -> UInt64 { 1 << t.rawValue }
        let mask: CGEventMask =
            maskBit(.leftMouseDown) | maskBit(.rightMouseDown)
            | maskBit(.keyDown)

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            onFinish?(false)
            return
        }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    public func stop(finished: Bool = false) {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            }
        }
        tap = nil
        runLoopSource = nil
        onFinish?(finished)
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable after system-imposed timeouts so picking never dies silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.escapeKeyCode) {
            stop(finished: true)
            return nil // swallow the Escape
        }

        switch type {
        case .leftMouseDown, .rightMouseDown:
            // Our own UI must stay clickable while picking.
            if WindowScanner.ownsPoint(cgLocation: event.location) {
                return Unmanaged.passUnretained(event)
            }
            count += 1
            onPoint?(event.location)
            if singleShot { stop(finished: true) }
            return nil // swallowed — picking clicks never click through
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
