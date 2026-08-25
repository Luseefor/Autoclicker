import CoreGraphics
import AppKit

/// A real content window discovered via the CG window list.
public struct WindowInfo: Sendable, Equatable, Identifiable {
    public var id: Int { windowId }
    public let windowId: Int
    public let pid: pid_t
    public let ownerName: String
    public let bundleId: String?
    /// Empty when Screen Recording permission is absent (macOS hides titles).
    public let title: String
    /// Global coordinates, top-left origin.
    public let bounds: CGRect
    public let layer: Int
    /// Currently composited somewhere (its own Space, visible or covered).
    /// False for minimized-to-Dock windows — background clicks cannot reach
    /// those until they're restored onto some Space.
    public let isOnScreen: Bool

    public init(
        windowId: Int, pid: pid_t, ownerName: String,
        bundleId: String?, title: String, bounds: CGRect, layer: Int,
        isOnScreen: Bool = true
    ) {
        self.windowId = windowId
        self.pid = pid
        self.ownerName = ownerName
        self.bundleId = bundleId
        self.title = title
        self.bounds = bounds
        self.layer = layer
        self.isOnScreen = isOnScreen
    }

    public var area: Double {
        max(0, bounds.width) * max(0, bounds.height)
    }
}

/// CGWindowList scanning with bundle-id enrichment.
public enum WindowScanner {

    private static let skippedOwners: Set<String> = [
        "window server", "dock", "control center", "notification center",
        "systemuiserver", "spotlight", "loginwindow",
    ]

    /// - Parameter onScreenOnly: false includes minimized / other-Space
    ///   windows — required so target selection works for background apps.
    public static func allWindows(
        onScreenOnly: Bool = false,
        minSize: CGSize = CGSize(width: 120, height: 80),
        layer0Only: Bool = true,
        skipSystemOwners: Bool = true
    ) -> [WindowInfo] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        options.insert(onScreenOnly ? .optionOnScreenOnly : .optionAll)
        guard
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        var seen = Set<Int>()
        var out: [WindowInfo] = []
        for w in raw {
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            if layer0Only && layer != 0 { continue }

            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            if skipSystemOwners && skippedOwners.contains(owner.lowercased()) {
                continue
            }
            let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? 0
            let id = (w[kCGWindowNumber as String] as? Int) ?? 0
            if id == 0 || seen.contains(id) { continue }

            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let bx = b["X"], let by = b["Y"],
                  let bw = b["Width"], let bh = b["Height"]
            else { continue }
            if bw < minSize.width || bh < minSize.height { continue }

            // Alpha-0 surfaces are invisible overlays.
            if let alpha = w[kCGWindowAlpha as String] as? CGFloat, alpha < 0.05 {
                continue
            }

            seen.insert(id)
            let isOnScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            out.append(
                WindowInfo(
                    windowId: id,
                    pid: pid_t(pid),
                    ownerName: owner,
                    bundleId: bundleIdForPID(pid_t(pid)),
                    title: (w[kCGWindowName as String] as? String) ?? "",
                    bounds: CGRect(x: bx, y: by, width: bw, height: bh),
                    layer: layer,
                    isOnScreen: isOnScreen
                )
            )
        }
        return out.sorted { $0.area > $1.area }
    }

    /// Filtered lookup, largest-area first.
    public static func windows(
        pid: pid_t? = nil,
        bundleId: String? = nil,
        titleContains: String? = nil,
        onScreenOnly: Bool = false
    ) -> [WindowInfo] {
        allWindows(onScreenOnly: onScreenOnly).filter { w in
            if let pid, w.pid != pid { return false }
            if let bundleId, w.bundleId != bundleId { return false }
            if let titleContains, !w.title.localizedCaseInsensitiveContains(titleContains) {
                return false
            }
            return true
        }
    }

    /// Best-match window for a target description.
    /// `find_window` fallback chain (id → bundle → name → title).
    public static func findWindow(
        bundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        windowId: Int? = nil
    ) -> WindowInfo? {
        if let windowId,
           let exact = allWindows(minSize: CGSize(width: 2, height: 2))
           .first(where: { $0.windowId == windowId }) {
            return exact
        }

        var candidates = allWindows()
        if let bundleId {
            let matched = candidates.filter { $0.bundleId == bundleId }
            if !matched.isEmpty {
                candidates = matched
            } else if let appName {
                candidates = candidates.filter {
                    $0.ownerName.caseInsensitiveCompare(appName) == .orderedSame
                }
            } else {
                return nil
            }
        } else if let appName {
            candidates = candidates.filter {
                $0.ownerName.caseInsensitiveCompare(appName) == .orderedSame
            }
        }

        if let windowTitle {
            let titled = candidates.filter {
                $0.title.localizedCaseInsensitiveContains(windowTitle)
            }
            if !titled.isEmpty { return titled.first }
        }
        return candidates.first
    }

    public static func frontmostWindow() -> WindowInfo? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        return windows(pid: front.processIdentifier, onScreenOnly: true).first
    }

    public static func bundleIdForPID(_ pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// True when the given pid belongs to this process tree.
    public static func isOwnProcess(_ pid: pid_t) -> Bool {
        pid == getpid() || bundleIdForPID(pid) == Bundle.main.bundleIdentifier
    }

    /// True when a global CG point (top-left origin) lands on this process's
    /// **topmost** window. Z-order aware: another app's window overlapping our
    /// frame owns the click when it sits in front — capture taps must count
    /// those, not swallow them as "our UI".
    public static func ownsPoint(cgLocation: CGPoint) -> Bool {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        for w in raw {   // listed front-to-back
            if (w[kCGWindowLayer as String] as? Int) ?? 0 != 0 { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"],
                  let width = b["Width"], let height = b["Height"] else { continue }
            if CGRect(x: x, y: y, width: width, height: height).contains(cgLocation) {
                let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? 0
                return pid == getpid()
            }
        }
        return false
    }
}
