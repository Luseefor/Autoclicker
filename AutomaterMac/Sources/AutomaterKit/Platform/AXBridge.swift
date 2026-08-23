import ApplicationServices
import Foundation

/// Accessibility trust checks and point→pid hit-testing.
public enum AXBridge {

    public static var isTrustedForAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system prompt; returns current trust state.
    @discardableResult
    public static func requestAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// PIDs that should receive an event at this point: the app pid plus the
    /// renderer/child pid when the AX hit lands in web content (WebKit,
    /// Chromium). Mirrors the Python `_pids_at_point` behavior.
    public static func hitTestPIDs(appPID: pid_t, x: CGFloat, y: CGFloat) -> [pid_t] {
        var pids: [pid_t] = [appPID]
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element)
        guard err == .success, let element else { return pids }

        var ownerPid: pid_t = 0
        if AXUIElementGetPid(element, &ownerPid) == .success,
           ownerPid != 0, ownerPid != appPID {
            pids.append(ownerPid)
        }
        return pids
    }

    /// Forces Chromium/Electron-family apps to build their full web
    /// accessibility tree. Without this they expose only layout containers.
    public static func enableAccessibility(appPID: pid_t) {
        let appElement = AXUIElementCreateApplication(appPID)
        let value = kCFBooleanTrue as CFTypeRef
        // Chromium honors AXEnhancedUserInterface; Electron honors
        // AXManualAccessibility. Set both, ignore which applies.
        AXUIElementSetAttributeValue(
            appElement, "AXEnhancedUserInterface" as CFString, value
        )
        AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, value
        )
    }

    /// True once the app's AX tree resolves any element at this point — used
    /// to detect lazily-built trees (Chromium builds one only after a query).
    public static func hasElementAt(appPID: pid_t, x: CGFloat, y: CGFloat) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        return AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element) == .success
            && element != nil
    }

    /// Human-readable dump of the AX element chain at a point (debugging).
    public static func describeElementAt(appPID: pid_t, x: CGFloat, y: CGFloat) -> String {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element)
        guard err == .success, let start = element else {
            return "no element (err \(err.rawValue))"
        }
        var lines: [String] = []
        var current = start
        for depth in 0..<8 {
            let role = stringAttr(current, kAXRoleAttribute)
            let title = stringAttr(current, kAXTitleAttribute)
            let label = stringAttr(current, kAXDescriptionAttribute)
            var actions: CFArray?
            let acts = (AXUIElementCopyActionNames(current, &actions) == .success)
                ? ((actions as? [String])?.joined(separator: ",")) ?? "" : "err"
            lines.append("\(depth): role=\(role) title='\(title)' desc='\(label)' actions=[\(acts)]")
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
            current = unsafeDowncast(p, to: AXUIElement.self)
        }
        return lines.joined(separator: "\n")
    }

    private static func stringAttr(_ el: AXUIElement, _ name: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
              let s = v as? String else { return "" }
        return s
    }

    /// True background click: perform the AXPress action on the element under
    /// the point (walking ancestors when the hit surface itself isn't
    /// pressable). Works regardless of window focus or event routing.
    @discardableResult
    public static func pressAt(appPID: pid_t, x: CGFloat, y: CGFloat) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element) == .success,
              let start = element else { return false }

        var current = start
        for _ in 0..<8 {
            var actions: CFArray?
            if AXUIElementCopyActionNames(current, &actions) == .success,
               let list = actions as? [String], list.contains("AXPress") {
                return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
            current = unsafeDowncast(p, to: AXUIElement.self)
        }
        return false
    }
}
