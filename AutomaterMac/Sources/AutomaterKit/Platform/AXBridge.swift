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
}
