import CoreGraphics
import AppKit
import Foundation

/// Records mouse + keyboard into MacroSteps via a listen-only CGEventTap.
///
/// Smart coalescing keeps macros human-sized:
/// - held keys collapse into ONE step carrying hold_ms (no repeat spam)
/// - continuous scrolling collapses into ONE step carrying scroll duration
/// - three-finger swipes record as directional "swipe" steps
public final class EventTapRecorder {
    public private(set) var steps: [MacroStep] = []
    public var onSteps: (([MacroStep]) -> Void)?
    public var onStatus: ((String) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMonitor: Any?

    // press state
    private var pressPos: CGPoint?
    private var pressButton: MouseButton = .left
    private var pressTime: TimeInterval = 0
    private var dragMoved = false
    // relative-delay capture (mirrors the Python recorder's _elapsed_ms)
    private var lastEventTime: TimeInterval?
    // keyboard chord state
    private var heldMods: Set<String> = []
    private var comboPending: String?
    // open key press (for repeat-coalescing and hold duration)
    private var keyDownInfo: (key: String, time: TimeInterval, id: Int)?
    // open scroll burst (continuous scrolling coalesces into one step)
    private var scrollPending: (dx: Int, dy: Int, start: TimeInterval, last: TimeInterval, id: Int)?
    private var lastBurstNotify: TimeInterval = 0
    // key code → name reverse map
    private static let namesByKeycode: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        for (n, c) in KeyCodeMap.allNames { if m[c] == nil { m[c] = n } }
        return m
    }()

    public var recording: Bool { tap != nil }

    public init() {}

    public func clear() {
        withLock {
            steps.removeAll()
            keyDownInfo = nil
            scrollPending = nil
        }
        onSteps?(steps)
    }

    public func start() {
        guard tap == nil else { return }
        clear()
        lastEventTime = nil
        func maskBit(_ t: CGEventType) -> UInt64 { 1 << t.rawValue }
        let mask: CGEventMask =
            maskBit(.leftMouseDown) | maskBit(.leftMouseUp)
            | maskBit(.rightMouseDown) | maskBit(.rightMouseUp)
            | maskBit(.otherMouseDown) | maskBit(.otherMouseUp)
            | maskBit(.scrollWheel)
            | maskBit(.keyDown) | maskBit(.keyUp)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            Unmanaged<EventTapRecorder>.fromOpaque(refcon).takeUnretainedValue()
                .handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            onStatus?("Recorder needs Accessibility permission")
            return
        }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)

        // Three-finger swipes (Spaces / Mission Control) don't come through
        // the CG tap as usable events — NSEvent's global monitor does.
        gestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe]) {
            [weak self] event in
            self?.handleSwipe(dx: event.deltaX, dy: event.deltaY)
        }

        onStatus?("Recording…")
    }

    public func stop() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            }
        }
        tap = nil
        runLoopSource = nil
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        gestureMonitor = nil
        keyDownInfo = nil
        scrollPending = nil
        onStatus?("Recorded \(steps.count) steps")
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // Never record interactions with our own UI (Stop button, name
        // fields, etc.) — mirrors the Python recorder's ignore_pids.
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .scrollWheel, .keyDown, .keyUp:
            if WindowScanner.ownsPoint(cgLocation: event.location) { return }
        default:
            break
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            endScrollBurst()
            pressPos = event.location
            pressButton = Self.button(for: type)
            pressTime = Date().timeIntervalSince1970
            dragMoved = false

        case .mouseMoved:
            guard let start = pressPos else { return }
            let dx = abs(event.location.x - start.x)
            let dy = abs(event.location.y - start.y)
            if dx > 8 || dy > 8 { dragMoved = true }

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            handleMouseUp(at: event.location, upType: type)

        case .scrollWheel:
            handleScroll(event)

        case .keyDown, .keyUp:
            handleKey(type: type, event: event)

        default:
            break
        }
    }

    // MARK: scrolling — bursts become one step with a duration

    private func handleScroll(_ event: CGEvent) {
        let now = Date().timeIntervalSince1970
        // Axis1 = vertical (dy), Axis2 = horizontal (dx)
        let dx = Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let dy = Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        guard dx != 0 || dy != 0 else { return }

        withLock {
            if let p = scrollPending,
               sign(p.dx) == sign(dx), sign(p.dy) == sign(dy),
               now - p.last < 0.3 {
                // same continuous gesture — extend the duration, don't add steps
                steps[p.id].holdMs = Int((now - p.start) * 1000)
                scrollPending?.last = now
                notifyThrottledLocked(now: now)
                return
            }
            let delay = takeDelayMs(now: now)
            appendLocked(MacroStep(
                type: "scroll",
                x: Int(event.location.x), y: Int(event.location.y),
                delayMs: delay, dx: dx, dy: dy
            ))
            scrollPending = (dx, dy, now, now, steps.count - 1)
        }
    }

    /// A non-scroll event breaks the burst; the step already carries its
    /// final duration, so just drop the pointer.
    private func endScrollBurst() {
        withLock { scrollPending = nil }
    }

    private func sign(_ v: Int) -> Int { v > 0 ? 1 : v < 0 ? -1 : 0 }

    private func notifyThrottledLocked(now: TimeInterval) {
        guard now - lastBurstNotify > 0.15 else { return }
        lastBurstNotify = now
        onSteps?(steps)
    }

    // MARK: swipes (three-finger gestures)

    private func handleSwipe(dx: CGFloat, dy: CGFloat) {
        guard recording, abs(dx) > 0.05 || abs(dy) > 0.05 else { return }
        endScrollBurst()
        let now = Date().timeIntervalSince1970
        let delay = takeDelayMs(now: now)
        append(MacroStep(
            type: "swipe",
            delayMs: delay,
            dx: dx < 0 ? -1 : dx > 0 ? 1 : 0,
            dy: dy < 0 ? -1 : dy > 0 ? 1 : 0
        ))
    }

    // MARK: keyboard — chords, repeats collapse into holds

    private func handleKey(type: CGEventType, event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let name = Self.namesByKeycode[UInt16(clamping: code)]
            ?? "vk_\(code)"

        let modName: String? = {
            switch name {
            case "cmd", "command": return "cmd"
            case "ctrl", "control": return "ctrl"
            case "alt", "option", "opt": return "alt"
            case "shift": return "shift"
            default: return nil
            }
        }()

        if type == .keyDown {
            if let m = modName { heldMods.insert(m); return }

            // Key repeat (holding a key): collapse — the open key_down step
            // already represents it.
            var isRepeat = false
            withLock {
                if let info = keyDownInfo, info.key == name { isRepeat = true }
            }
            if isRepeat { return }

            endScrollBurst()
            let now = Date().timeIntervalSince1970
            let delay = takeDelayMs(now: now)
            if !heldMods.isEmpty {
                if comboPending == name { return } // held chord repeat
                let order = ["ctrl", "alt", "shift", "cmd"]
                let combo = (order.filter { heldMods.contains($0) } + [name]).joined(separator: "+")
                append(MacroStep(type: "key", key: combo, delayMs: delay))
                comboPending = name
            } else {
                withLock {
                    appendLocked(MacroStep(type: "key_down", key: name, delayMs: delay))
                    keyDownInfo = (name, now, steps.count - 1)
                }
            }
        } else if type == .keyUp {
            if let m = modName { heldMods.remove(m); return }
            if comboPending == name { comboPending = nil; return }

            let now = Date().timeIntervalSince1970
            var holdMs = 0
            if let info = keyDownInfo, info.key == name {
                holdMs = Int((now - info.time) * 1000)
                if holdMs < 250 { holdMs = 0 } // normal typing isn't a "hold"
            }
            keyDownInfo = nil
            withLock {
                if let last = steps.last, last.type == "key_down", last.key == name {
                    steps.removeLast()
                    appendLocked(MacroStep(type: "key", key: name,
                                           delayMs: last.delayMs, holdMs: holdMs))
                    return
                }
                appendLocked(MacroStep(type: "key_up", key: name, delayMs: 0))
            }
        }
    }

    private let lock = NSRecursiveLock()

    /// Gap attributed to a new step: wall-clock ms since the previous event,
    /// clamped so an accidental pause while recording can't stall replays.
    static let maxStepDelayMs = 5_000

    static func stepDelay(gapMs: Int?) -> Int {
        guard let gapMs, gapMs > 0 else { return 0 }
        return min(gapMs, maxStepDelayMs)
    }

    private func takeDelayMs(now: TimeInterval) -> Int {
        let gapMs = lastEventTime.map { Int((now - $0) * 1000) }
        lastEventTime = now
        return Self.stepDelay(gapMs: gapMs)
    }

    private func append(_ step: MacroStep) {
        lock.lock(); defer { lock.unlock() }
        appendLocked(step)
    }

    private func appendLocked(_ step: MacroStep) {
        steps.append(step)
        onSteps?(steps)
    }

    private func withLock(_ body: () -> Void) {
        lock.lock(); body(); lock.unlock()
    }

    // MARK: - Helpers

    private func handleMouseUp(at loc: CGPoint, upType: CGEventType) {
        guard let start = pressPos else { return }
        let now = Date().timeIntervalSince1970
        let holdMs = Int((now - pressTime) * 1000)
        let delay = takeDelayMs(now: now)
        let btn = pressButton.rawValue

        if dragMoved || abs(loc.x - start.x) > 8 || abs(loc.y - start.y) > 8 {
            append(MacroStep(
                type: "drag",
                x: Int(start.x), y: Int(start.y), button: btn,
                delayMs: delay,
                endX: Int(loc.x), endY: Int(loc.y)
            ))
        } else if holdMs >= 400 {
            append(MacroStep(
                type: "hold", x: Int(start.x), y: Int(start.y),
                button: btn, delayMs: delay, holdMs: holdMs
            ))
        } else {
            append(MacroStep(
                type: "click", x: Int(start.x), y: Int(start.y),
                button: btn, delayMs: delay, clickKind: "single"
            ))
        }
        pressPos = nil
    }

    static func button(for type: CGEventType) -> MouseButton {
        switch type {
        case .rightMouseDown, .rightMouseUp: return .right
        case .otherMouseDown, .otherMouseUp: return .middle
        default: return .left
        }
    }
}
