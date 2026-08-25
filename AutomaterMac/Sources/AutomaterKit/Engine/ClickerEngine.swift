import CoreGraphics
import Foundation
import os

/// Outcome of resolving a background delivery destination.
public struct ResolvedTarget: Sendable, Equatable {
    public var pid: pid_t?
    public var windowNumber: Int?

    static let none = ResolvedTarget(pid: nil, windowNumber: nil)
}

/// Background clicker worker: current-cursor, fixed-point, and multi-point
/// modes with true pointer-free background delivery.
public actor ClickerEngine {

    private static let log = Logger(
        subsystem: "com.luseefor.automater", category: "engine"
    )

    public private(set) var isRunning = false
    public private(set) var clicksPerformed = 0

    private var task: Task<Void, Never>?
    private let poster = EventPoster()

    public init() {}

    public nonisolated var isBusy: Bool {
        get async { await isRunning }
    }

    public func start(
        config: ClickerConfig,
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        stop(silent: true)
        clicksPerformed = 0
        isRunning = true
        onStatus("Clicker ON" + (config.backgroundToApp ? " (background app)" : ""))

        task = Task { [weak self] in
            await self?.runLoop(config: config, onStatus: onStatus)
            onStatus("Clicker OFF")
            guard let self else { return }
            await self.finish()
        }
    }

    public func stop(silent: Bool = false) {
        task?.cancel()
        task = nil
        if isRunning {
            isRunning = false
            if !silent { /* status emitted by loop teardown */ }
        }
    }

    private func finish() {
        isRunning = false
        task = nil
    }

    // MARK: - Loop

    private func runLoop(
        config: ClickerConfig,
        onStatus: @escaping @Sendable (String) -> Void
    ) async {
        let baseInterval = Double(max(1, config.intervalMs)) / 1000.0
        var done = 0
        var pointIndex = 0
        var didWarmUp = false
        // Report each distinct delivery issue once per session (no spam).
        var reportedIssues: Set<String> = []
        func reportOnce(_ msg: String) {
            guard !reportedIssues.contains(msg) else { return }
            reportedIssues.insert(msg)
            onStatus(msg)
        }

        while !Task.isCancelled {
            if config.repeatCount > 0 && done >= config.repeatCount { break }

            do {
                try Task.checkCancellation()

                var resolvedPoint: CGPoint?
                var bgTarget = ResolvedTarget.none

                switch config.mode {
                case .currentCursor:
                    let loc = EventPoster.cursorLocation
                    resolvedPoint = CGPoint(x: loc.x, y: loc.y)
                    if config.backgroundToApp {
                        bgTarget = Self.resolveBackgroundTarget(
                            pid: config.targetPid,
                            bundleId: config.appBundleId,
                            appName: config.appName,
                            title: config.windowTitle,
                            windowId: config.targetWindowId
                        )
                        if bgTarget.pid == nil {
                            onStatus("Background target not found")
                        }
                    }

                case .fixedPoint:
                    if let p = Self.resolveFixedPoint(config: config) {
                        resolvedPoint = p.point
                        if config.backgroundToApp {
                            bgTarget = Self.resolveBackgroundTarget(
                                pid: config.targetPid,
                                bundleId: config.appBundleId,
                                appName: config.appName,
                                title: config.windowTitle,
                                windowId: config.targetWindowId ?? config.fixedWindowId
                            )
                            if bgTarget.pid == nil {
                                onStatus("Background target not found")
                            }
                        }
                    } else {
                        onStatus("Target window not found")
                    }

                case .multipoint:
                    guard !config.multipoints.isEmpty else {
                        onStatus("No multi-points set")
                        break
                    }
                    let spec = config.multipoints[pointIndex % config.multipoints.count]
                    pointIndex += 1
                    if let p = Self.resolvePointSpec(spec) {
                        resolvedPoint = p.point
                        if config.backgroundToApp {
                        bgTarget = Self.resolveBackgroundTarget(
                            pid: spec.pid ?? config.targetPid,
                            bundleId: spec.appBundleId ?? config.appBundleId,
                            appName: spec.appName ?? config.appName,
                            title: spec.windowTitle ?? config.windowTitle,
                            windowId: spec.windowId ?? config.targetWindowId
                        )
                            if bgTarget.pid == nil {
                                onStatus("Background target not found")
                            }
                        }
                    } else {
                        onStatus("Target window not found")
                    }
                }

                guard let point = resolvedPoint else {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }

                // Chromium-family apps build their AX tree lazily on first
                // query; poke until an element resolves (max ~3s) so neither
                // AX presses nor event routing get swallowed. The flags are
                // safe for native apps too (verified: Calculator keeps its
                // tree) — the poke must always run or lazy trees never build.
                if config.backgroundToApp, let pid = bgTarget.pid, !didWarmUp {
                    didWarmUp = true
                    AXBridge.enableAccessibility(appPID: pid)
                    for _ in 0..<20 {
                        if AXBridge.hasElementAt(appPID: pid, x: point.x, y: point.y) {
                            break
                        }
                        try await Task.sleep(nanoseconds: 150_000_000)
                        try Task.checkCancellation()
                    }
                    try await Task.sleep(nanoseconds: 300_000_000)
                    try Task.checkCancellation()
                }

                deliver(point: point, target: bgTarget, config: config,
                        report: reportOnce)
                clicksPerformed += 1
                done += 1
            } catch is CancellationError {
                break
            } catch {
                Self.log.error("click loop error: \(error.localizedDescription, privacy: .public)")
                onStatus("Clicker error: \(error.localizedDescription)")
                break
            }

            // Interval with jitter, cancellable. Task.sleep only throws on
            // cancellation here.
            var wait = baseInterval
            if config.jitterMs > 0 {
                wait += Double(Int.random(in: -config.jitterMs...config.jitterMs)) / 1000.0
                wait = max(0.001, wait)
            }
            do {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    /// Delivers one click. AX misses (fully-covered windows in AX-hostile
    /// apps) automatically fall back to pid-routed synthetic events.
    private func deliver(
        point: CGPoint, target: ResolvedTarget, config: ClickerConfig,
        report: (String) -> Void
    ) {
        if config.backgroundToApp, let pid = target.pid {
            switch config.deliveryMode {
            case .accessibility:
                let landed = poster.axClick(x: point.x, y: point.y, pid: pid,
                                            button: config.button, kind: config.clickKind)
                if landed { return }
                // Tier 2: route synthetic events into the process — reaches
                // covered windows that expose no pressable AX elements.
                let children = AXBridge.hitTestPIDs(appPID: pid, x: point.x, y: point.y)
                poster.backgroundClick(
                    x: point.x, y: point.y,
                    pid: pid,
                    childPIDs: Array(children.dropFirst()),
                    windowNumber: target.windowNumber,
                    button: config.button,
                    kind: config.clickKind
                )
                Self.log.info("AX unreachable at (\(Int(point.x)),\(Int(point.y))) pid \(pid) — routed synthetic-event fallback")
                report("Target obscured — using synthetic-event fallback (games like Roblox ignore this; use foreground delivery)")
            case .events:
                let children = AXBridge.hitTestPIDs(appPID: pid, x: point.x, y: point.y)
                poster.backgroundClick(
                    x: point.x, y: point.y,
                    pid: pid,
                    childPIDs: Array(children.dropFirst()),
                    windowNumber: target.windowNumber,
                    button: config.button,
                    kind: config.clickKind
                )
            }
        } else {
            poster.foregroundClick(
                x: point.x, y: point.y,
                button: config.button,
                kind: config.clickKind
            )
        }
    }

    // MARK: - Point resolution (static: no isolation needed)

    /// Returns (screenPoint, windowUsedForLocalResolution).
    static func resolveFixedPoint(config: ClickerConfig) -> (point: CGPoint, window: WindowInfo?)? {
        if config.fixedCoordSpace == .window {
            let window = WindowScanner.findWindow(
                bundleId: config.appBundleId,
                appName: config.appName,
                windowTitle: config.windowTitle,
                windowId: config.fixedWindowId
            )
            guard let window else { return nil }
            let p = localToScreen(
                localX: config.fixedLocalX, localY: config.fixedLocalY, in: window
            )
            return (p, window)
        }
        return (CGPoint(x: config.fixedScreenX, y: config.fixedScreenY), nil)
    }

    static func resolvePointSpec(_ spec: PointSpec) -> (point: CGPoint, window: WindowInfo?)? {
        if spec.coordSpace == .window {
            let window = WindowScanner.findWindow(
                bundleId: spec.appBundleId,
                appName: spec.appName,
                windowTitle: spec.windowTitle,
                windowId: spec.windowId
            )
            guard let window else { return nil }
            let lx = spec.localX ?? 0
            let ly = spec.localY ?? 0
            return (localToScreen(localX: lx, localY: ly, in: window), window)
        }
        if let x = spec.x, let y = spec.y {
            return (CGPoint(x: x, y: y), nil)
        }
        return nil
    }

    static func localToScreen(localX: Double, localY: Double, in window: WindowInfo) -> CGPoint {
        CGPoint(x: window.bounds.minX + localX, y: window.bounds.minY + localY)
    }

    /// Explicit pid wins (verified alive); otherwise identity lookup.
    public static func resolveBackgroundTarget(
        pid: Int?,
        bundleId: String?,
        appName: String?,
        title: String?,
        windowId: Int?
    ) -> ResolvedTarget {
        if let pid, pid > 0, kill(pid_t(pid), 0) == 0 {
            let wins = WindowScanner.windows(pid: pid_t(pid))
            // Prefer the explicitly targeted window when it belongs to this
            // pid, so event routing doesn't jump to whichever window happens
            // to be largest.
            let winNumber = windowId.flatMap { id in
                wins.first(where: { $0.windowId == id })?.windowId
            } ?? wins.first?.windowId ?? windowId
            return ResolvedTarget(pid: pid_t(pid), windowNumber: winNumber)
        }
        if let window = WindowScanner.findWindow(
            bundleId: bundleId, appName: appName,
            windowTitle: title, windowId: windowId
        ) {
            return ResolvedTarget(pid: window.pid, windowNumber: window.windowId)
        }
        return .none
    }
}
