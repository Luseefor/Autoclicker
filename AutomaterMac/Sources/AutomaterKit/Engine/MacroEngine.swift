import CoreGraphics
import Foundation

/// Plays Macro steps — foreground or background, with loops and speed.
public actor MacroEngine {
    public private(set) var isPlaying = false
    private var task: Task<Void, Never>?
    private let poster = EventPoster()

    public init() {}

    public func play(
        macro: Macro,
        backgroundToApp: Bool = false,
        deliveryMode: ClickerConfig.DeliveryMode = .accessibility,
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        stop(silent: true)
        isPlaying = true
        onStatus("Playing: \(macro.name)")

        let macro = macro
        task = Task { [weak self] in
            var iteration = 0
            while !Task.isCancelled {
                iteration += 1
                if macro.loopCount > 0 && iteration > macro.loopCount { break }
                for step in macro.steps {
                    if Task.isCancelled { break }
                    await self?.run(step: step, macro: macro,
                                    bg: backgroundToApp, mode: deliveryMode)
                    let delay = Double(max(0, step.delayMs)) / 1000.0
                        / max(0.05, macro.speed)
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }
            onStatus(Task.isCancelled ? "Stopped" : "Playback finished")
            guard let self else { return }
            await self.finish()
        }
    }

    public func stop(silent: Bool = false) {
        task?.cancel()
        task = nil
        if isPlaying { isPlaying = false }
    }

    private func finish() {
        isPlaying = false
        task = nil
    }

    // MARK: - Step execution

    private func run(
        step: MacroStep, macro: Macro,
        bg: Bool, mode: ClickerConfig.DeliveryMode
    ) async {
        switch step.type {
        case "delay":
            break // handled by caller

        case "click":
            guard let p = resolvePoint(step, macro: macro) else { return }
            click(p, step: step, macro: macro, bg: bg, mode: mode)

        case "hold":
            await hold(step, macro: macro, bg: bg)

        case "drag":
            await drag(step, macro: macro, bg: bg)

        case "move":
            guard let p = resolvePoint(step, macro: macro) else { return }
            poster.moveCursor(x: p.x, y: p.y)

        case "scroll":
            // Mirror the Python engine: optionally move to the step position,
            // then post a two-axis line-unit scroll (dx horizontal, dy vertical).
            if step.x != nil || step.coordSpace == "window" {
                if let p = resolvePoint(step, macro: macro) {
                    poster.moveCursor(x: p.x, y: p.y)
                }
            }
            poster.scroll(dx: step.dx ?? 0, dy: step.dy ?? 0)

        case "key", "key_down", "key_up":
            key(step, bg: bg, macro: macro, mode: mode)

        case "type":
            typeText(step.text ?? "")

        default:
            break
        }
    }

    // MARK: resolution helpers

    private func targetWindow(_ step: MacroStep, _ macro: Macro) -> WindowInfo? {
        WindowScanner.findWindow(
            bundleId: step.appBundleId ?? macro.targetAppBundleId,
            appName: step.appName ?? macro.targetAppName,
            windowTitle: step.windowTitle ?? macro.targetWindowTitle,
            windowId: step.windowId
        )
    }

    private func resolvePoint(_ step: MacroStep, macro: Macro) -> CGPoint? {
        if step.coordSpace == "window" {
            guard let w = targetWindow(step, macro) else { return nil }
            return CGPoint(x: w.bounds.minX + (step.localX ?? 0),
                           y: w.bounds.minY + (step.localY ?? 0))
        }
        if let x = step.x, let y = step.y { return CGPoint(x: x, y: y) }
        let loc = EventPoster.cursorLocation
        return CGPoint(x: loc.x, y: loc.y)
    }

    private func bgTarget(_ step: MacroStep, _ macro: Macro) -> ResolvedTarget {
        ClickerEngine.resolveBackgroundTarget(
            pid: nil,
            bundleId: step.appBundleId ?? macro.targetAppBundleId,
            appName: step.appName ?? macro.targetAppName,
            title: step.windowTitle ?? macro.targetWindowTitle,
            windowId: step.windowId
        )
    }

    // MARK: delivery

    private func click(
        _ p: CGPoint, step: MacroStep, macro: Macro,
        bg: Bool, mode: ClickerConfig.DeliveryMode
    ) {
        let kind = ClickKind(rawValue: step.clickKind) ?? .single
        let button = MouseButton(rawValue: step.button ?? "left") ?? .left

        if bg {
            let target = bgTarget(step, macro)
            guard let pid = target.pid else {
                poster.foregroundClick(x: p.x, y: p.y, button: button, kind: kind)
                return
            }
            AXBridge.enableAccessibility(appPID: pid)
            switch mode {
            case .accessibility:
                for _ in 0..<kind.presses {
                    AXBridge.pressAt(appPID: pid, x: p.x, y: p.y)
                    if kind.presses > 1 { Thread.sleep(forTimeInterval: 0.05) }
                }
            case .events:
                poster.backgroundClick(x: p.x, y: p.y, pid: pid,
                                       windowNumber: target.windowNumber,
                                       button: button, kind: kind)
            }
        } else {
            poster.foregroundClick(x: p.x, y: p.y, button: button, kind: kind)
        }
    }

    private static func downEvent(for button: MouseButton) -> CGEventType {
        switch button {
        case .right: return .rightMouseDown
        case .middle: return .otherMouseDown
        case .left: return .leftMouseDown
        }
    }

    private static func upEvent(for button: MouseButton) -> CGEventType {
        switch button {
        case .right: return .rightMouseUp
        case .middle: return .otherMouseUp
        case .left: return .leftMouseUp
        }
    }

    private func hold(_ step: MacroStep, macro: Macro, bg: Bool) async {
        guard let p = resolvePoint(step, macro: macro) else { return }
        let button = MouseButton(rawValue: step.button ?? "left") ?? .left
        let target = bg ? bgTarget(step, macro) : ResolvedTarget.none

        func deliver(_ type: CGEventType) {
            poster.postMouseEvent(type, x: p.x, y: p.y, button: button,
                                  pid: target.pid,
                                  windowNumber: target.windowNumber)
        }

        deliver(Self.downEvent(for: button))
        // Hold duration scales with playback speed like every other delay.
        let secs = Double(max(0, step.holdMs)) / 1000.0 / max(0.05, macro.speed)
        do { try await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000)) } catch {}
        deliver(Self.upEvent(for: button))
    }

    /// AXPress cannot express press-and-move, so background drags always use
    /// pid-routed synthetic events (same choice as the Python engine).
    private func drag(_ step: MacroStep, macro: Macro, bg: Bool) async {
        guard let start = resolvePoint(step, macro: macro) else { return }
        let end: CGPoint?
        if step.coordSpace == "window" {
            end = targetWindow(step, macro).map {
                CGPoint(x: $0.bounds.minX + (step.endLocalX ?? 0),
                        y: $0.bounds.minY + (step.endLocalY ?? 0))
            }
        } else if let ex = step.endX, let ey = step.endY {
            end = CGPoint(x: ex, y: ey)
        } else {
            end = nil
        }
        guard let end else { return }
        let button = MouseButton(rawValue: step.button ?? "left") ?? .left
        let target = bg ? bgTarget(step, macro) : ResolvedTarget.none

        func deliver(_ type: CGEventType, _ x: Double, _ y: Double, clickState: Int) {
            poster.postMouseEvent(type, x: x, y: y, button: button,
                                  pid: target.pid, clickState: clickState,
                                  windowNumber: target.windowNumber)
        }

        if target.pid == nil {
            poster.warpCursor(x: start.x, y: start.y)
            poster.moveCursor(x: start.x, y: start.y)
        }
        deliver(Self.downEvent(for: button), start.x, start.y, clickState: 1)

        // Interpolation density scales inversely with speed at a fixed 10ms
        // cadence (matches the Python engine's max(5, int(20 / speed))).
        let stepCount = Self.interpolationSteps(speed: macro.speed)
        do {
            for i in 1...stepCount {
                let t = Double(i) / Double(stepCount)
                let x = start.x + (end.x - start.x) * t
                let y = start.y + (end.y - start.y) * t
                deliver(.mouseMoved, x, y, clickState: 0)
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch {
            // Cancelled mid-drag — the release below still runs so the
            // button never sticks down.
        }
        deliver(Self.upEvent(for: button), end.x, end.y, clickState: 1)
    }

    static func interpolationSteps(speed: Double) -> Int {
        max(5, Int((20.0 / max(0.05, speed)).rounded(.down)))
    }

    private func key(_ step: MacroStep, bg: Bool, macro: Macro, mode: ClickerConfig.DeliveryMode) {
        let combo = step.key ?? ""
        if bg, let pid = bgTarget(step, macro).pid {
            if EventPoster().keyCombo(combo, pid: pid) { return }
        }
        // Global fallback via chord presses.
        let parts = combo.split(separator: "+").map(String.init)
        guard !parts.isEmpty else { return }
        var mods: [String] = []
        var tail: String?
        for part in parts {
            let lowered = part.lowercased()
            if Self.modifierNames.contains(lowered) {
                mods.append(lowered)
            } else { tail = part }
        }
        guard let tail else { return }
        pressChord(mods: mods, tail: tail,
                   downOnly: step.type == "key_down",
                   upOnly: step.type == "key_up")
    }

    private static let modifierNames: Set<String> = ["cmd", "ctrl", "alt", "shift"]

    private func pressChord(mods: [String], tail: String,
                            downOnly: Bool, upOnly: Bool) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = []
        let codes = mods.compactMap { KeyCodeMap.keycode(for: $0) }
        for c in codes { flags.insert(Self.flag(forVirtual: c)) }
        guard let tailCode = KeyCodeMap.keycode(for: tail) else { return }

        func post(_ code: UInt16, _ down: Bool) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
            if !flags.isEmpty { e.flags = flags }
            e.post(tap: .cghidEventTap)
        }
        if !upOnly { for c in codes { post(c, true) } ; post(tailCode, true) }
        if !downOnly {
            post(tailCode, false)
            for c in codes.reversed() { post(c, false) }
        }
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

    /// Unicode typing via event string payload (covers any character).
    private func typeText(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for ch in text {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            let utf = Array(ch.utf16)
            down.keyboardSetUnicodeString(stringLength: utf.count, unicodeString: utf)
            up.keyboardSetUnicodeString(stringLength: utf.count, unicodeString: utf)
            down.post(tap: .cghidEventTap)
            usleep(8000)
            up.post(tap: .cghidEventTap)
            usleep(12000)
        }
    }
}
