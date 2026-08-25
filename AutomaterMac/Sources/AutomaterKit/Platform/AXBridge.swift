import ApplicationServices
import AppKit
import Foundation

/// Accessibility trust checks and point→pid hit-testing.
public enum AXBridge {

    public static var isTrustedForAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Opens System Settings → Privacy & Security → Accessibility directly.
    /// More reliable than the legacy API prompt, which ad-hoc-signed apps
    /// often never see.
    @discardableResult
    public static func openAccessibilitySettings() -> Bool {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Returns current trust state and lands the user on the Accessibility
    /// pane so they can grant immediately.
    @discardableResult
    public static func requestAccessibilityPrompt() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted { openAccessibilitySettings() }
        return trusted
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
    ///
    /// NEVER call this unconditionally: setting these flags on non-Chromium
    /// apps (Calculator, many AppKit apps) wipes their AX tree entirely.
    /// Gate behind needsLazyTreePoke(_:x:y:).
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

    /// True only when the app looks like a lazy-tree app: nothing resolvable
    /// at the point AND the containing window exposes no children. Healthy
    /// trees (Calculator, native apps) return false so their AX state is
    /// never touched.
    public static func needsLazyTreePoke(appPID: pid_t, x: CGFloat, y: CGFloat) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element) == .success,
           element != nil {
            return false
        }
        guard let window = windowContaining(appPID: appPID, x: x, y: y) else {
            return true // no resolvable tree at all — poke and hope
        }
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &kids) == .success,
           let children = kids as? [AXUIElement], !children.isEmpty {
            return false // window has a live subtree — leave it alone
        }
        return true
    }

    /// True once the app's AX tree resolves any element at this point — used
    /// to detect lazily-built trees (Chromium builds one only after a query).
    /// Falls back to frame containment for occluded/other-Space windows where
    /// position hit-testing reports nothing.
    public static func hasElementAt(appPID: pid_t, x: CGFloat, y: CGFloat) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element) == .success,
           element != nil {
            return true
        }
        return windowContaining(appPID: appPID, x: x, y: y) != nil
    }

    /// False when the app exposes no AX windows at all — typical of games
    /// (Roblox, Minecraft) which read raw hardware input and ignore both
    /// AXPress and pid-routed synthetic events. Foreground delivery is the
    /// only thing that works on those.
    public static func hasAXWindows(appPID: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &value
        ) == .success else { return false }
        return (value as? [AXUIElement])?.isEmpty == false
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
    ///
    /// Position hit-testing fails for occluded/other-Space windows in many
    /// apps, so a miss falls back to walking the AX tree by frame — the tree
    /// is queryable even when the window isn't composited on top.
    @discardableResult
    public static func pressAt(appPID: pid_t, x: CGFloat, y: CGFloat) -> Bool {
        let appElement = AXUIElementCreateApplication(appPID)
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(appElement, Float(x), Float(y), &element) == .success,
           let start = element,
           pressAncestorChain(from: start) {
            return true
        }

        // Cached element from a previous tree-walk at (roughly) this point?
        let cacheKey = CacheKey(pid: appPID, cx: Int(x / 8), cy: Int(y / 8))
        cacheLock.lock()
        let cached = elementCache[cacheKey]
        cacheLock.unlock()
        if let cached {
            if pressAncestorChain(from: cached) { return true }
            cacheLock.lock()
            elementCache[cacheKey] = nil
            cacheLock.unlock()
        }

        guard let found = treeWalkPressable(appPID: appPID, x: x, y: y),
              pressAncestorChain(from: found) else { return false }
        cacheLock.lock()
        elementCache[cacheKey] = found
        cacheLock.unlock()
        return true
    }

    private struct CacheKey: Hashable {
        let pid: pid_t
        let cx: Int
        let cy: Int
    }

    private static let cacheLock = NSLock()
    private static var elementCache: [CacheKey: AXUIElement] = [:]

    /// Performs AXPress on the element, walking up to 8 ancestors for the
    /// first one that supports the action.
    private static func pressAncestorChain(from start: AXUIElement) -> Bool {
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

    // MARK: occluded-window tree walk

    private static func axFrame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
            let pos = posRef,
            AXValueGetType(pos as! AXValue) == .cgPoint,
            AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let size = sizeRef,
            AXValueGetType(size as! AXValue) == .cgSize
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    /// Topmost AX window of the app whose frame contains the point.
    ///
    /// Chromium browsers (Brave/Chrome) on modern macOS expose no usable
    /// kAXWindowsAttribute — the real window hangs off AXFocusedWindow
    /// (per-app state, works even when the app is covered), so it joins the
    /// candidates. Windows with live children are preferred over dummies.
    private static func windowContaining(appPID: pid_t, x: CGFloat, y: CGFloat) -> AXUIElement? {
        let app = AXUIElementCreateApplication(appPID)
        let point = CGPoint(x: x, y: y)
        var candidates: [AXUIElement] = []

        var cfWindows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &cfWindows) == .success,
           let windows = cfWindows as? [AXUIElement] {
            for window in windows.reversed() {  // last = topmost
                if let f = axFrame(window), f.contains(point) { candidates.append(window) }
            }
        }

        var focusedRef: CFTypeRef?
        var focusedWindow: AXUIElement?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let ref = focusedRef, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            focusedWindow = unsafeDowncast(ref, to: AXUIElement.self)
        }
        if let fw = focusedWindow,
           let f = axFrame(fw), f.contains(point),
           !candidates.contains(where: { $0 == fw }) {
            candidates.append(fw)
        }

        for window in candidates {
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &kids) == .success,
               let children = kids as? [AXUIElement], !children.isEmpty {
                return window
            }
        }
        return candidates.first
    }

    /// Depth-limited search for the deepest pressable element containing the
    /// point, starting from a window. Later children are checked first
    /// (they render on top).
    private static func treeWalkPressable(appPID: pid_t, x: CGFloat, y: CGFloat) -> AXUIElement? {
        guard let window = windowContaining(appPID: appPID, x: x, y: y) else { return nil }
        return searchPressable(window, x: x, y: y, depth: 0)
    }

    private static func searchPressable(_ el: AXUIElement, x: CGFloat, y: CGFloat, depth: Int) -> AXUIElement? {
        if depth > 12 { return nil }
        guard let f = axFrame(el), f.contains(CGPoint(x: x, y: y)) else { return nil }

        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
           let children = kids as? [AXUIElement] {
            for child in children.reversed() {
                if let hit = searchPressable(child, x: x, y: y, depth: depth + 1) { return hit }
            }
        }
        var actions: CFArray?
        if AXUIElementCopyActionNames(el, &actions) == .success,
           let list = actions as? [String], list.contains("AXPress") {
            return el
        }
        return nil
    }
}
