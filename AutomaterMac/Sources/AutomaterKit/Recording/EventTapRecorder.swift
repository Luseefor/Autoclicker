import CoreGraphics
import AppKit
import Foundation

/// Records mouse + keyboard into MacroSteps via a listen-only CGEventTap.
public final class EventTapRecorder {
    public private(set) var steps: [MacroStep] = []
    public var onSteps: (([MacroStep]) -> Void)?
    public var onStatus: ((String) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?

    // press state
    private var pressPos: CGPoint?
    private var pressButton: MouseButton = .left
    private var pressTime: TimeInterval = 0
    private var dragMoved = false
    // keyboard chord state
    private var heldMods: Set<String> = []
    private var comboPending: String?
    // key code → name reverse map
    private static let namesByKeycode: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        for (n, c) in KeyCodeMap.allNames { if m[c] == nil { m[c] = n } }
        return m
    }()

    public var recording: Bool { tap != nil }

    public init() {}

    public func clear() {
        steps.removeAll()
        onSteps?(steps)
    }

    public func start() {
        guard tap == nil else { return }
        clear()
        func maskBit(_ t: CGEventType) -> UInt64 { 1 << t.rawValue }
        let mask: CGEventMask =
            maskBit(.leftMouseDown) | maskBit(.leftMouseUp)
            | maskBit(.rightMouseDown) | maskBit(.rightMouseUp)
            | maskBit(.otherMouseDown) | maskBit(.otherMouseUp)
            | maskBit(.scrollWheel)
            | maskBit(.keyDown) | maskBit(.keyUp)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            Unmanaged<EventTapRecorder>.fromOpaque(refcon!).takeUnretainedValue()
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
        onStatus?("Recorded \(steps.count) steps")
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
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
            append(MacroStep(
                type: "scroll",
                x: Int(event.location.x), y: Int(event.location.y),
                // Axis1 = vertical (11), Axis2 = horizontal (12)
                dx: Int(event.getIntegerValueField(CGEventField(rawValue: 12)!)),
                dy: Int(event.getIntegerValueField(CGEventField(rawValue: 11)!))
            ))

        case .keyDown, .keyUp:
            handleKey(type: type, event: event)

        default:
            break
        }
    }

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
            let delay = 0
            if !heldMods.isEmpty {
                let order = ["ctrl", "alt", "shift", "cmd"]
                let combo = (order.filter { heldMods.contains($0) } + [name]).joined(separator: "+")
                append(MacroStep(type: "key", key: combo, delayMs: delay))
                comboPending = name
            } else {
                append(MacroStep(type: "key_down", key: name, delayMs: delay))
            }
        } else if type == .keyUp {
            if let m = modName { heldMods.remove(m); return }
            if comboPending == name { comboPending = nil; return }
            withLock {
                if let last = steps.last, last.type == "key_down", last.key == name {
                    steps.removeLast()
                    appendLocked(MacroStep(type: "key", key: name, delayMs: last.delayMs))
                    return
                }
                appendLocked(MacroStep(type: "key_up", key: name, delayMs: 0))
            }
        }
    }

    private let lock = NSRecursiveLock()

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
        let btn = pressButton.rawValue

        if dragMoved || abs(loc.x - start.x) > 8 || abs(loc.y - start.y) > 8 {
            append(MacroStep(
                type: "drag",
                x: Int(start.x), y: Int(start.y), button: btn,
                endX: Int(loc.x), endY: Int(loc.y)
            ))
        } else if holdMs >= 400 {
            append(MacroStep(
                type: "hold", x: Int(start.x), y: Int(start.y),
                button: btn, holdMs: holdMs
            ))
        } else {
            append(MacroStep(
                type: "click", x: Int(start.x), y: Int(start.y),
                button: btn, clickKind: "single"
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
