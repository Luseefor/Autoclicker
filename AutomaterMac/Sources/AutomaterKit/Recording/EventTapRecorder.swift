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

    // press state
    private var pressPos: CGPoint?
    private var pressButton: MouseButton = .left
    private var pressTime: TimeInterval = 0
    private var dragMoved = false
    // relative-delay capture
    private var lastEventTime: TimeInterval?
    // keyboard chord state
    private var heldMods: Set<String> = []
    private var comboPending: String?
    // bare-modifier taps: mods pressed & released without any chord
    private var tappedMods: [String] = []
    private var chordUsedMods = false
    // open gesture (three-finger swipe coalescing)
    private var gesturePending: (dxSum: Double, dySum: Double, last: TimeInterval, id: Int)?
    // open key press (for repeat-coalescing and hold duration)
    private var keyDownInfo: (key: String, time: TimeInterval, id: Int)?
    // Plain text is kept as a compact `type` step.  Remember the physical
    // keys until their matching keyUp arrives so it is not recorded as an
    // orphaned `key_up` step.
    private var typedKeyNames: Set<String> = []
    private var lastTypedTime: TimeInterval?
    // open scroll burst (continuous scrolling coalesces into one step)
    private var scrollPending: (dx: Int, dy: Int, start: TimeInterval, last: TimeInterval, id: Int)?
    private var lastBurstNotify: TimeInterval = 0
    /// App hotkey chords (normalized) — pressing them while recording must
    /// NOT end up inside the macro (e.g. ⌃⌥R that stops the recording).
    public var ignoredCombos: Set<String> = []
    private var ignoredKeyUp: String?
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
            gesturePending = nil
            ignoredKeyUp = nil
            typedKeyNames.removeAll()
            lastTypedTime = nil
        }
        onSteps?(steps)
    }

    public func start() {
        guard tap == nil else { return }
        clear()
        lastEventTime = nil

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            Unmanaged<EventTapRecorder>.fromOpaque(refcon).takeUnretainedValue()
                .handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        func maskBit(_ t: CGEventType) -> UInt64 { 1 << t.rawValue }
        let mask: CGEventMask =
            maskBit(.leftMouseDown) | maskBit(.leftMouseUp)
            | maskBit(.rightMouseDown) | maskBit(.rightMouseUp)
            | maskBit(.otherMouseDown) | maskBit(.otherMouseUp)
            | maskBit(.scrollWheel)
            | maskBit(.keyDown) | maskBit(.keyUp)
            | maskBit(.flagsChanged)
            // trackpad gesture stream (three-finger swipes etc.) — raw values
            // 29 (kCGEventGesture) / 31 (kCGEventSwipe); not in the Swift overlay
            | (1 << 29) | (1 << 31)

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
        keyDownInfo = nil
        scrollPending = nil
        gesturePending = nil
        ignoredKeyUp = nil
        typedKeyNames.removeAll()
        lastTypedTime = nil
        onStatus?("Recorded \(steps.count) steps")
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // Never record interactions with our own UI.
        // recorder's ignore_pids. Mouse/scroll: cursor over our topmost
        // window. Keyboard: our app has focus (cursor position is irrelevant
        // for key events — modifiers were wrongly dropped otherwise).
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            if WindowScanner.ownsPoint(cgLocation: event.location) { return }
        case .keyDown, .keyUp, .flagsChanged:
            // During recording Automater hides its own UI but can remain the
            // active app briefly. Keep those keys; otherwise the first chord
            // entered in the target app is silently missing from the macro.
            if NSApplication.shared.isActive && !NSApplication.shared.isHidden { return }
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

        case .flagsChanged:
            // Modifiers arrive as flagsChanged, not keyDown/keyUp — derive
            // press/release from the event flags and feed the same path.
            handleFlagsChanged(event)

        case _ where type.rawValue == 29 || type.rawValue == 31:
            handleGesture(event)

        default:
            break
        }
    }

    /// flagsChanged → synthetic keyDown/keyUp for the modifier involved.
    private func handleFlagsChanged(_ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard let name = Self.namesByKeycode[UInt16(clamping: code)] else { return }
        let modName: String?
        switch name {
        case "cmd", "command": modName = "cmd"
        case "ctrl", "control": modName = "ctrl"
        case "alt", "option", "opt": modName = "alt"
        case "shift": modName = "shift"
        default: return // flagsChanged only carries modifiers
        }
        let f = event.flags
        let isDown: Bool
        switch modName! {
        case "cmd": isDown = f.contains(.maskCommand)
        case "ctrl": isDown = f.contains(.maskControl)
        case "alt": isDown = f.contains(.maskAlternate)
        case "shift": isDown = f.contains(.maskShift)
        default: return
        }
        handleKey(type: isDown ? .keyDown : .keyUp, event: event)
    }

    // MARK: gestures — three-finger swipes from the trackpad stream

    /// Undocumented but stable gesture fields: 123 = swipe delta, 124 = swipe
    /// direction. Delta sign gives horizontal direction; vertical falls back
    /// to the direction field.
    private static let gestureDeltaField = CGEventField(rawValue: 123)
    private static let gestureDirField = CGEventField(rawValue: 124)

    private func handleGesture(_ event: CGEvent) {
        if WindowScanner.ownsPoint(cgLocation: event.location) { return }
        var dx: Double = 0, dy: Double = 0
        if let f = Self.gestureDeltaField {
            dx = event.getDoubleValueField(f)
        }
        if dx == 0, let f = Self.gestureDirField {
            let d = event.getIntegerValueField(f)
            if d != 0 { dy = Double(d) }
        }
        guard dx != 0 || dy != 0 else { return }

        let now = Date().timeIntervalSince1970
        withLock {
            if let p = gesturePending, now - p.last < 0.35 {
                gesturePending?.dxSum += dx
                gesturePending?.dySum += dy
                gesturePending?.last = now
                steps[p.id].dx = sign(Int(p.dxSum + dx))
                steps[p.id].dy = sign(Int(p.dySum + dy))
                notifyThrottledLocked(now: now)
                return
            }
            scrollPending = nil
            let delay = takeDelayMs(now: now)
            // Some trackpads emit only one gesture event. Persist its first
            // direction immediately; waiting for a second event created a
            // visible but inert swipe step (0, 0).
            appendLocked(MacroStep(
                type: "swipe", delayMs: delay,
                dx: sign(Int(dx)), dy: sign(Int(dy))
            ))
            gesturePending = (dx, dy, now, steps.count - 1)
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
        withLock {
            scrollPending = nil
            gesturePending = nil
        }
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
        // Ignore device-specific keys that we cannot replay.  Recording them
        // as `key_down` / `key_up` made the macro look broken and added no
        // usable automation step.
        guard let name = Self.namesByKeycode[UInt16(clamping: code)] else { return }

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
            if let m = modName {
                // Track bare-modifier taps: mods released without any chord
                // record as their own step ("key cmd"), consumed chords don't.
                if heldMods.isEmpty {
                    tappedMods = [m]
                    chordUsedMods = false
                } else if !tappedMods.contains(m) {
                    tappedMods.append(m)
                }
                heldMods.insert(m)
                return
            }

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
            if heldMods.subtracting(["shift"]).isEmpty,
               let text = printableText(from: event) {
                appendTypedText(text, delayMs: delay, now: now)
                typedKeyNames.insert(name)
                return
            }
            if !heldMods.isEmpty {
                if comboPending == name { return } // held chord repeat
                let order = ["ctrl", "alt", "shift", "cmd"]
                let combo = (order.filter { heldMods.contains($0) } + [name]).joined(separator: "+")
                if ignoredCombos.contains(HotkeyManager.normalized(combo)) {
                    ignoredKeyUp = name // app hotkey — never record it
                    return
                }
                append(MacroStep(type: "key", key: combo, delayMs: delay))
                comboPending = name
                chordUsedMods = true
                tappedMods.removeAll()
            } else {
                withLock {
                    appendLocked(MacroStep(type: "key_down", key: name, delayMs: delay))
                    keyDownInfo = (name, now, steps.count - 1)
                }
            }
        } else if type == .keyUp {
            if let m = modName {
                heldMods.remove(m)
                // All mods released and nothing consumed them → bare tap.
                if heldMods.isEmpty, !chordUsedMods, !tappedMods.isEmpty {
                    let combo = tappedMods.joined(separator: "+")
                    tappedMods.removeAll()
                    chordUsedMods = false
                    if !ignoredCombos.contains(HotkeyManager.normalized(combo)) {
                        let delay = takeDelayMs(now: Date().timeIntervalSince1970)
                        append(MacroStep(type: "key", key: combo, delayMs: delay))
                    }
                } else if heldMods.isEmpty {
                    tappedMods.removeAll()
                    chordUsedMods = false
                }
                return
            }
            if comboPending == name { comboPending = nil; return }
            if ignoredKeyUp == name { ignoredKeyUp = nil; return }
            if typedKeyNames.remove(name) != nil { return }

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

    /// Returns text only for normal printable input.  Navigation keys,
    /// Return, Tab, and shortcuts remain discrete keyboard steps.
    private func printableText(from event: CGEvent) -> String? {
        var length = 0
        var buffer = Array<UniChar>(repeating: 0, count: 16)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: buffer, count: min(length, buffer.count))
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }

    /// Merge normal typing into a readable text step.  A pause still starts a
    /// new step so intentional timing between phrases is retained.
    private func appendTypedText(_ text: String, delayMs: Int, now: TimeInterval) {
        withLock {
            if let last = steps.indices.last,
               steps[last].type == "type",
               let lastTypedTime,
               now - lastTypedTime < 0.7 {
                steps[last].text = (steps[last].text ?? "") + text
                self.lastTypedTime = now
                onSteps?(steps)
                return
            }
            appendLocked(MacroStep(type: "type", text: text, delayMs: delayMs))
            lastTypedTime = now
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
