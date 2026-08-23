import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey — no Input Monitoring
/// permission required.
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private var hotkeys: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextId: UInt32 = 1

    private init() {}

    /// binding like "ctrl+alt+a"; returns false when unparsable/unregistered.
    @discardableResult
    public func register(_ binding: String, handler: @escaping () -> Void) -> Bool {
        guard let (mods, keyCode) = Self.parse(binding) else { return false }
        var hotKeyID = EventHotKeyID(signature: OSType(0x41555448 /*AUTH*/), id: nextId)
        var ref: EventHotKeyRef?
        let err = RegisterEventHotKey(
            keyCode, mods, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard err == noErr else { return false }
        hotkeys[nextId] = handler
        refs.append(ref)
        nextId += 1
        return true
    }

    public func unregisterAll() {
        for r in refs { if let r { UnregisterEventHotKey(r) } }
        refs.removeAll()
        hotkeys.removeAll()
    }

    private var installOnce: Bool = false
    public func installDispatcher() {
        guard !installOnce else { return }
        installOnce = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, _ in
            var id = EventHotKeyID()
            if let event, GetEventParameter(
                event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id
            ) == noErr {
                HotkeyManager.shared.dispatch(id: id.id)
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, nil, nil
        )
    }

    fileprivate func dispatch(id: UInt32) {
        hotkeys[id]?()
    }

    /// "ctrl+alt+a" → (mods, virtual keycode)
    static func parse(_ binding: String) -> (UInt32, UInt32)? {
        var mods: UInt32 = 0
        var key: UInt32?
        for raw in binding.split(separator: "+") {
            let token = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                .lowercased()
            switch token {
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "alt", "opt", "option": mods |= UInt32(optionKey)
            case "shift": mods |= UInt32(shiftKey)
            case "cmd", "command": mods |= UInt32(cmdKey)
            default:
                if let code = KeyCodeMap.keycode(for: token) { key = UInt32(code) }
            }
        }
        guard let key else { return nil }
        return (mods, key)
    }
}
