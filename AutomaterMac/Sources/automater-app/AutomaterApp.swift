import SwiftUI
import AppKit
import Combine
import os
import UserNotifications
import AutomaterKit

// MARK: - App entry

@main
struct AutomaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Automater") {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 560)
        }
        .commands { commands }

        Settings {
            SettingsView()
                .environmentObject(state)
        }

        MenuBarExtra("Automater", systemImage: "cursorarrow.click.2") {
            MenuBarControlsView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }

    /// Native menu-bar commands (in-app; global Carbon hotkeys are separate).
    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Macro") { state.newMacro() }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .newItem) {
            Button("Save Macro") { state.saveCurrentMacro() }
                .keyboardShortcut("s")
        }
        CommandMenu("Controls") {
            Button(state.isClicking ? "Stop Clicking" : "Start Clicking") {
                state.toggleClicker()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button(state.recorder.recording ? "Stop Recording" : "Record") {
                state.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command])
            Button("Play Current Macro") {
                let m = state.playableMacro()
                guard !m.steps.isEmpty else { return }
                state.play(macro: m)
            }
            .keyboardShortcut("p", modifiers: [.command])
            Divider()
            Button("Stop Everything") { state.stopAll() }
                .keyboardShortcut(".", modifiers: [.command])
        }
    }
}

/// A purpose-built status-bar control surface.  Keeping this as a window
/// rather than a stock menu gives the frequent actions enough hierarchy to be
/// understood at a glance, without opening the full app.
private struct MenuBarControlsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            action(
                title: state.isClicking ? "Stop clicker" : "Run clicker",
                subtitle: state.isClicking ? "Clicking is active" : clickerSummary,
                icon: state.isClicking ? "stop.fill" : "cursorarrow.click.2",
                tint: state.isClicking ? .red : .accentColor,
                action: state.toggleClicker
            )
            action(
                title: state.isRecording ? "Stop recording" : "Record macro",
                subtitle: state.isRecording ? "Capturing your actions" : "Capture clicks, keys, and text",
                icon: state.isRecording ? "stop.circle.fill" : "record.circle",
                tint: state.isRecording ? .red : .orange,
                action: state.toggleRecording
            )
            action(
                title: state.playingMacro ? "Stop macro" : "Play macro",
                subtitle: state.playingMacro ? "Macro playback is active" : macroSummary,
                icon: state.playingMacro ? "stop.circle.fill" : "play.circle.fill",
                tint: state.playingMacro ? .red : .purple,
                action: state.playToggle
            )
            Divider()
            Button(role: .destructive) { state.stopAll() } label: {
                Label("Stop All Automation", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            HStack(spacing: 8) {
                Button("Open Automater", systemImage: "macwindow") {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isClicking ? "cursorarrow.click.2" : "cursorarrow.click")
                .font(.title3.weight(.semibold))
                .foregroundStyle(state.isClicking ? .green : .accentColor)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Automater").font(.headline)
                Text(currentStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(currentStatus)
        }
    }

    private func action(
        title: String, subtitle: String, icon: String, tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var clickerSummary: String {
        "\(state.intervalTotalMs) ms · \(state.button.rawValue.capitalized) \(state.kind.rawValue)"
    }

    private var macroSummary: String {
        let count = state.playableMacro().steps.count
        return count == 0 ? "No steps ready" : "\(count) step\(count == 1 ? "" : "s") ready"
    }

    private var currentStatus: String {
        if state.isRecording { return "Recording macro" }
        if state.playingMacro { return "Playing macro" }
        if state.isClicking { return "Clicker running" }
        return state.status == "Idle" ? "Ready to automate" : state.status
    }

    private var statusColor: Color {
        state.isClicking || state.isRecording || state.playingMacro ? .green : .secondary
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(
        subsystem: "com.luseefor.automater", category: "hotkeys"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.installDispatcher()
        HotkeyCoordinator.registerAll(log: Self.log)
        installEditingDismiss()
    }

    /// Clicking anywhere outside a text field drops the caret. SwiftUI on
    /// macOS never resigns first responder on outside clicks, so the focus
    /// ring + blinking cursor would otherwise stick around forever.
    private func installEditingDismiss() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window,
                  let content = window.contentView,
                  let hit = content.hitTest(event.locationInWindow) else { return event }
            // Only act while a field editor is active, and never when the
            // click landed inside that editor itself.
            if window.firstResponder is NSTextView, !(hit is NSTextView) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }
}

/// Central registry of global-hotkey bindings: reads settings, registers with
/// Carbon, and can be re-run after a rebind (unregisters everything first).
enum HotkeyCoordinator {
    static let bindings: [(setting: String, fallback: String, label: String, action: Notification.Name)] = [
        ("hotkey_toggle", "ctrl+alt+a", "toggle clicker", .automaterToggle),
        ("hotkey_record", "ctrl+alt+r", "record", .automatorRecordToggle),
        ("hotkey_play", "ctrl+alt+p", "play/stop macro", .automaterPlayToggle),
        ("hotkey_stop", "ctrl+alt+s", "stop all", .automaterStopAll),
        ("hotkey_grab", "ctrl+alt+g", "grab point", .automaterGrabPoint),
    ]

    /// Every active binding, normalized — the recorder filters these out so
    /// hotkey presses never end up inside a recorded macro.
    static func activeCombos() -> Set<String> {
        let s = Storage.loadSettings()
        return Set(bindings.map {
            HotkeyManager.normalized(s[$0.setting] as? String ?? $0.fallback)
        })
    }

    static func binding(for setting: String) -> String {
        let s = Storage.loadSettings()
        return bindings.first(where: { $0.setting == setting })
            .map { s[$0.setting] as? String ?? $0.fallback } ?? ""
    }

    /// Persists a new binding for one hotkey and re-registers all of them.
    static func rebind(setting: String, to binding: String) {
        var s = Storage.loadSettings()
        s[setting] = binding
        Storage.saveSettings(s)
        registerAll()
    }

    static func registerAll(log: Logger? = nil) {
        let s = Storage.loadSettings()
        for b in bindings {
            let binding = s[b.setting] as? String ?? b.fallback
            let registered = HotkeyManager.shared.register(binding) {
                NotificationCenter.default.post(name: b.action, object: nil)
            }
            if !registered {
                log?.error("hotkey '\(binding, privacy: .public)' (\(b.label, privacy: .public)) failed to register — likely in use by another app")
                NotificationCenter.default.post(
                    name: .automaterStatus,
                    object: "Hotkey \(binding) (\(b.label)) failed to register"
                )
            }
        }
    }
}

extension Notification.Name {
    static let automaterToggle = Notification.Name("automaterToggle")
    static let automatorRecordToggle = Notification.Name("automatorRecordToggle")
    static let automaterStopAll = Notification.Name("automaterStopAll")
    static let automaterGrabPoint = Notification.Name("automaterGrabPoint")
    static let automaterPlayToggle = Notification.Name("automaterPlayToggle")
    /// `object` carries a user-facing status message (String).
    static let automaterStatus = Notification.Name("automaterStatus")
}

// MARK: - State

/// One row of the Target tab's app table.
struct RunningApp: Identifiable {
    let app: NSRunningApplication
    let name: String
    var id: Int32 { app.processIdentifier }
}

/// A conservative preflight result. This reports whether macOS exposes a
/// supported background-delivery path; it never claims that an app accepted a
/// click, because many apps do not expose an acknowledgement for that.
enum BackgroundCompatibility {
    case noTarget
    case likely
    case syntheticOnly
    case foregroundRecommended

    var title: String {
        switch self {
        case .noTarget: return "No target"
        case .likely: return "Background likely supported"
        case .syntheticOnly: return "Synthetic-event delivery"
        case .foregroundRecommended: return "Foreground recommended"
        }
    }

    var detail: String {
        switch self {
        case .noTarget:
            return "Choose a target app before checking compatibility."
        case .likely:
            return "The target exposes macOS accessibility windows. Smart background delivery can try an accessibility action first."
        case .syntheticOnly:
            return "This target previously ignored accessibility actions. Automater will use synthetic background events, which the app may still reject."
        case .foregroundRecommended:
            return "The target exposes no usable accessibility windows. Background delivery is unlikely to work; use foreground mode."
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // Clicker
    @Published var intervalH = 0
    @Published var intervalM = 0
    @Published var intervalS = 0
    @Published var intervalMs = 100
    @Published var jitterMs = 0
    @Published var repeatCount = 0
    @Published var button: MouseButton = .left
    @Published var kind: ClickKind = .single
    @Published var mode: ClickerConfig.Mode = .multipoint
    @Published var fixedX = 0
    @Published var fixedY = 0
    @Published var backgroundToApp = true
    @Published var deliveryMode: ClickerConfig.DeliveryMode = .accessibility

    @Published var multipoints: [PointSpec] = []
    @Published var status = "Idle"
    @Published var isClicking = false

    // Target
    @Published var targetWindow: WindowInfo?
    @Published var runningApps: [RunningApp] = []
    @Published var windowsOfTarget: [WindowInfo] = []

    // Macros / recorder
    @Published var macros: [Macro] = []
    @Published var currentMacro = Macro(name: "New macro")
    @Published var recordedSteps: [MacroStep] = []
    @Published var isRecording = false
    @Published var playingMacro = false
    @Published var selectedAppID: Int32?
    @Published var selectedWindowID: Int?
    @Published var selectedMacroID: String?
    @Published var useRecordedForPlay = true

    let engine = ClickerEngine()
    let macroEngine = MacroEngine()
    let recorder = EventTapRecorder()
    let pointPicker = PointPicker()
    let fixedPointPicker = PointPicker()
    let fixedPointOverlay = FixedPointOverlayController()
    private var cancellables = Set<AnyCancellable>()

    @Published var isPicking = false
    @Published var isCapturingFixedPoint = false
    @Published var hasFixedPoint = false

    var backgroundCompatibility: BackgroundCompatibility {
        guard let targetWindow else { return .noTarget }
        let key = targetWindow.bundleId ?? "pid:\(targetWindow.pid)"
        if Storage.loadDeliveryMemory()[key] == "events" {
            return .syntheticOnly
        }
        return AXBridge.hasAXWindows(appPID: targetWindow.pid)
            ? .likely : .foregroundRecommended
    }

    func checkBackgroundCompatibility() {
        let result = backgroundCompatibility
        status = "\(result.title): \(result.detail)"
    }

    init() {
        loadFromSettings()
        refreshApps()
        refreshMacros()

        recorder.onSteps = { [weak self] steps in
            Task { @MainActor in self?.recordedSteps = steps }
        }
        recorder.onStatus = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }

        pointPicker.onPoint = { [weak self] loc in
            Task { @MainActor in
                guard let self else { return }
                let spec = PointSpec(x: Int(loc.x), y: Int(loc.y),
                                     pid: self.targetWindow.map { Int($0.pid) })
                self.multipoints.append(spec)
                self.status = "Picked \(self.multipoints.count): (\(Int(loc.x)), \(Int(loc.y)))"
            }
        }
        pointPicker.onFinish = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                NSApp.unhide(nil)
                self.isPicking = false
                if finished {
                    let n = self.multipoints.count
                    self.status = n == 0 ? "Picking ended — no points" : "\(n) point\(n == 1 ? "" : "s") picked"
                } else {
                    self.status = "Point picking needs Accessibility"
                }
            }
        }

        // Fixed point: single-shot capture + neon laser overlay tracking.
        fixedPointPicker.singleShot = true
        fixedPointPicker.onPoint = { [weak self] loc in
            Task { @MainActor in
                guard let self else { return }
                self.fixedX = Int(loc.x)
                self.fixedY = Int(loc.y)
                self.hasFixedPoint = true
                self.status = "Fixed point (\(self.fixedX), \(self.fixedY))"
            }
        }
        fixedPointPicker.onFinish = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                NSApp.unhide(nil)
                self.isCapturingFixedPoint = false
                if !finished { self.status = "Fixed-point capture needs Accessibility" }
            }
        }
        Publishers.CombineLatest4($mode, $hasFixedPoint, $fixedX, $fixedY)
            .sink { [weak self] mode, has, x, y in
                guard let self else { return }
                self.fixedPointOverlay.setVisible(
                    mode == .fixedPoint && has,
                    at: CGPoint(x: Double(x), y: Double(y))
                )
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: .automaterToggle)
            .sink { [weak self] _ in self?.toggleClicker() }
            .store(in: &cancellables)
        center.publisher(for: .automatorRecordToggle)
            .sink { [weak self] _ in self?.toggleRecording() }
            .store(in: &cancellables)
        center.publisher(for: .automaterStopAll)
            .sink { [weak self] _ in self?.stopAll() }
            .store(in: &cancellables)
        center.publisher(for: .automaterGrabPoint)
            .sink { [weak self] _ in self?.handleGrabHotkey() }
            .store(in: &cancellables)
        center.publisher(for: .automaterPlayToggle)
            .sink { [weak self] _ in self?.playToggle() }
            .store(in: &cancellables)
        center.publisher(for: .automaterStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let msg = note.object as? String { self?.status = msg }
            }
            .store(in: &cancellables)
    }

    // MARK: settings round-trip

    func loadFromSettings() {
        let s = Storage.loadSettings()
        intervalH = s["click_interval_h"] as? Int ?? 0
        intervalM = s["click_interval_m"] as? Int ?? 0
        intervalS = s["click_interval_s"] as? Int ?? 0
        intervalMs = s["click_interval_ms"] as? Int ?? 100
        jitterMs = s["jitter_ms"] as? Int ?? 0
        repeatCount = s["repeat_count"] as? Int ?? 0
        button = MouseButton(rawValue: s["mouse_button"] as? String ?? "left") ?? .left
        kind = ClickKind(rawValue: s["click_kind"] as? String ?? "single") ?? .single
        mode = ClickerConfig.Mode(rawValue: s["mode"] as? String ?? "multipoint") ?? .multipoint
        backgroundToApp = s["background_to_app"] as? Bool ?? true
        deliveryMode = ClickerConfig.DeliveryMode(
            rawValue: s["delivery_mode"] as? String ?? "accessibility"
        ) ?? .accessibility
    }

    func persistSettings() {
        var s = Storage.defaults
        s["click_interval_h"] = intervalH
        s["click_interval_m"] = intervalM
        s["click_interval_s"] = intervalS
        s["click_interval_ms"] = intervalMs
        s["jitter_ms"] = jitterMs
        s["repeat_count"] = repeatCount
        s["mouse_button"] = button.rawValue
        s["click_kind"] = kind.rawValue
        s["mode"] = mode.rawValue
        s["background_to_app"] = backgroundToApp
        s["delivery_mode"] = deliveryMode.rawValue
        Storage.saveSettings(s)
    }

    // MARK: clicker

    /// Total interval in ms — computed over the h/m/s/ms buckets that
    /// settings persist. The Clicker UI edits this through a unit picker.
    var intervalTotalMs: Int {
        get { ((intervalH * 60 + intervalM) * 60 + intervalS) * 1000 + intervalMs }
        set {
            intervalH = newValue / 3_600_000
            intervalM = newValue % 3_600_000 / 60_000
            intervalS = newValue % 60_000 / 1000
            intervalMs = newValue % 1000
        }
    }

    func buildConfig() -> ClickerConfig {
        var config = ClickerConfig()
        config.intervalMs = ((intervalH * 60 + intervalM) * 60 + intervalS) * 1000 + intervalMs
        config.jitterMs = jitterMs
        config.repeatCount = repeatCount
        config.button = button
        config.clickKind = kind
        config.mode = mode
        config.fixedScreenX = fixedX
        config.fixedScreenY = fixedY
        if let tw = targetWindow {
            config.appName = tw.ownerName
            config.windowTitle = tw.title.isEmpty ? nil : tw.title
            config.targetPid = Int(tw.pid)
            config.targetWindowId = tw.windowId
        }
        config.multipoints = multipoints
        config.backgroundToApp = backgroundToApp
        config.deliveryMode = deliveryMode
        return config
    }

    /// Below this the engine clamps to a near-busy-loop; refuse instead.
    static let minimumIntervalMs = 10

    func toggleClicker() {
        if isClicking { stopClicker(); return }
        endPicking()
        endFixedCapture()
        stopRecording()
        guard AXBridge.isTrustedForAccessibility else {
            status = "Grant Accessibility first"
            AXBridge.requestAccessibilityPrompt()
            return
        }
        persistSettings()
        let config = buildConfig()
        if config.mode == .multipoint && config.multipoints.isEmpty {
            status = "Add multi-points first"
            return
        }
        guard config.intervalMs >= Self.minimumIntervalMs else {
            status = "Interval too short — minimum \(Self.minimumIntervalMs) ms"
            return
        }
        isClicking = true
        Task {
            await engine.start(config: config) { [weak self] msg in
                Task { @MainActor in self?.status = msg }
            }
            while await engine.isRunning { try? await Task.sleep(nanoseconds: 120_000_000) }
            await MainActor.run { self.isClicking = false }
        }
    }

    func stopClicker() {
        Task {
            await engine.stop(silent: true)
            await MainActor.run { isClicking = false; status = "Stopped" }
        }
    }

    func stopAll() {
        endPicking()
        endFixedCapture()
        stopClicker()
        stopRecording()
        Task {
            await macroEngine.stop()
            await MainActor.run { playingMacro = false }
        }
    }

    func toggleFloatingControls() {
        FloatingControls.toggle(state: self)
    }

    func grabFixedPoint() {
        let loc = EventPoster.cursorLocation
        fixedX = Int(loc.x)
        fixedY = Int(loc.y)
        hasFixedPoint = true
        status = "Fixed point (\(fixedX), \(fixedY))"
    }

    // MARK: fixed-point capture (arm, then click the real target)

    /// The Grab button can't grab its own position — arming captures the
    /// user's NEXT click anywhere instead. (Hover + ⌃⌥G also works.)
    func toggleFixedPointCapture() {
        if isCapturingFixedPoint {
            fixedPointPicker.stop(finished: true)
            return
        }
        guard AXBridge.isTrustedForAccessibility else {
            status = "Grant Accessibility first"
            AXBridge.requestAccessibilityPrompt()
            return
        }
        fixedPointPicker.start()
        isCapturingFixedPoint = fixedPointPicker.active
        if isCapturingFixedPoint {
            status = "Click anywhere to set the fixed point — Esc to cancel"
        }
    }

    private func endFixedCapture() {
        if isCapturingFixedPoint { fixedPointPicker.stop(finished: true) }
    }

    /// Hides the laser marker (overlay clears via the mode/point sink).
    func clearFixedPoint() {
        endFixedCapture()
        hasFixedPoint = false
        status = "Fixed point cleared"
    }

    /// ⌃⌥G from anywhere: hover over a spot and press — no button click
    /// needed (clicking the UI would move the cursor onto the button).
    /// Contextual: feeds the Fixed Point field in that mode, otherwise
    /// appends a multi-point.
    func handleGrabHotkey() {
        if mode == .fixedPoint {
            grabFixedPoint()
        } else {
            addPointAtCursor()
        }
    }

    // MARK: point picking (click-to-capture)

    func togglePicking() {
        if isPicking {
            pointPicker.stop(finished: true)
            return
        }
        guard AXBridge.isTrustedForAccessibility else {
            status = "Grant Accessibility first"
            AXBridge.requestAccessibilityPrompt()
            return
        }
        pointPicker.start()
        isPicking = pointPicker.active
        if isPicking {
            status = "Picking points — click to add, Esc to finish"
        }
    }

    private func endPicking() {
        if isPicking { pointPicker.stop(finished: true) }
    }

    func addPointAtCursor() {
        let loc = EventPoster.cursorLocation
        let pidValue = targetWindow.map { Int($0.pid) }
        let spec = PointSpec(x: Int(loc.x), y: Int(loc.y), pid: pidValue)
        let px = spec.x ?? 0
        let py = spec.y ?? 0
        multipoints.append(spec)
        status = "Point \(multipoints.count) at (\(px), \(py))"
    }

    func removeSelectedPoints(at offsets: IndexSet) {
        multipoints.remove(atOffsets: offsets)
    }

    // MARK: target picker

    func selectApp(id: Int32?) {
        guard let id, let app = NSRunningApplication(processIdentifier: id) else { return }
        selectedAppID = id
        select(app: app)
    }

    func selectWindow(id: Int?) {
        guard let id, let w = windowsOfTarget.first(where: { $0.windowId == id }) else { return }
        selectedWindowID = id
        setTarget(w)
    }

    func selectMacro(id: String?) {
        guard let id, let m = macros.first(where: { $0.id == id }) else { return }
        selectedMacroID = id
        loadMacro(m)
    }

    func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                return RunningApp(app: app, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func select(app: NSRunningApplication) {
        let wins = WindowScanner.windows(pid: app.processIdentifier)
        windowsOfTarget = wins
        if let first = wins.first {
            setTarget(first)
        } else {
            // No scannable windows: keep an app-level pseudo-target
            // (windowId -1 matches no real window) so background delivery can
            // still resolve the app by name/bundle/pid via the fallback chain.
            setTarget(WindowInfo(
                windowId: -1, pid: app.processIdentifier,
                ownerName: app.localizedName ?? "", bundleId: app.bundleIdentifier,
                title: "", bounds: .zero, layer: 0
            ))
        }
    }

    func setTarget(_ w: WindowInfo) {
        targetWindow = w
        windowsOfTarget = WindowScanner.windows(pid: w.pid)
        status = "Target: \(w.ownerName)" + (w.title.isEmpty ? "" : " — \(w.title)")
    }

    // MARK: recorder

    func toggleRecording() {
        if isRecording { stopRecording(); return }
        guard AXBridge.isTrustedForAccessibility else {
            status = "Recorder needs Accessibility"
            AXBridge.requestAccessibilityPrompt()
            return
        }
        // The app's own hotkeys (⌃⌥R stop, ⌃⌥P play, …) must never leak
        // into the recording.
        recorder.ignoredCombos = HotkeyCoordinator.activeCombos()
        recordedSteps = []
        recorder.start()
        isRecording = recorder.recording
        if isRecording {
            status = "Recording… press the record hotkey to stop"
            hideForInputCapture()
        }
    }

    func stopRecording() {
        guard recorder.recording else { return }
        recorder.stop()
        isRecording = false
        NSApp.unhide(nil)
    }

    private func hideForInputCapture() {
        // Let the global event tap/picker start before hiding our own window,
        // so the next click or keystroke belongs to the real target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.hide(nil)
        }
    }

    /// ⌃⌥P — play the current macro; press again to stop mid-playback.
    func playToggle() {
        if playingMacro {
            Task {
                await macroEngine.stop()
                await MainActor.run {
                    playingMacro = false
                    status = "Playback stopped"
                }
            }
            return
        }
        let macro = playableMacro()
        guard !macro.steps.isEmpty else {
            status = "Nothing to play — record or load a macro first"
            return
        }
        play(macro: macro)
    }

    // MARK: macros

    func refreshMacros() {
        macros = Storage.listMacros()
    }

    func saveCurrentMacro() {
        currentMacro.steps = currentMacro.id.isEmpty
            ? recordedSteps : (recordedSteps.isEmpty ? currentMacro.steps : recordedSteps)
        if Storage.saveMacro(currentMacro) {
            refreshMacros()
            status = "Saved “\(currentMacro.name)”"
        } else {
            status = "Failed to save “\(currentMacro.name)” — see logs"
        }
    }

    func newMacro() {
        currentMacro = Macro(name: "Macro \(macros.count + 1)")
        recordedSteps = []
    }

    func deleteCurrentMacro() {
        Storage.deleteMacro(id: currentMacro.id)
        refreshMacros()
        newMacro()
    }

    func play(macro: Macro) {
        guard AXBridge.isTrustedForAccessibility else {
            status = "Grant Accessibility first"
            return
        }
        playingMacro = true
        Task {
            await macroEngine.play(
                macro: macro,
                backgroundToApp: backgroundToApp,
                deliveryMode: deliveryMode
            ) { [weak self] msg in
                Task { @MainActor in self?.status = msg }
            }
            while await macroEngine.isPlaying { try? await Task.sleep(nanoseconds: 150_000_000) }
            await MainActor.run { self.playingMacro = false }
        }
    }
}
