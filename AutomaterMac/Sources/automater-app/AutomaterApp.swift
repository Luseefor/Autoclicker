import SwiftUI
import AppKit
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
        .windowStyle(.automatic)

        MenuBarExtra("Automater", systemImage: "cursorarrow.click.2") {
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button(state.isClicking ? "Stop clicker" : "Start clicker") {
                state.toggleClicker()
            }
            .keyboardShortcut("a", modifiers: [.control, .option])
            Button(state.recorder.recording ? "Stop recording" : "Start recording") {
                state.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.control, .option])
            Button("Stop everything") { state.stopAll() }
                .keyboardShortcut("s", modifiers: [.control, .option])
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.installDispatcher()
        let s = Storage.loadSettings()
        _ = HotkeyManager.shared.register(
            s["hotkey_toggle"] as? String ?? "ctrl+alt+a"
        ) { NotificationCenter.default.post(name: .automaterToggle, object: nil) }
        _ = HotkeyManager.shared.register(
            s["hotkey_record"] as? String ?? "ctrl+alt+r"
        ) { NotificationCenter.default.post(name: .automatorRecordToggle, object: nil) }
        _ = HotkeyManager.shared.register(
            s["hotkey_stop"] as? String ?? "ctrl+alt+s"
        ) { NotificationCenter.default.post(name: .automaterStopAll, object: nil) }
    }
}

extension Notification.Name {
    static let automaterToggle = Notification.Name("automaterToggle")
    static let automatorRecordToggle = Notification.Name("automatorRecordToggle")
    static let automaterStopAll = Notification.Name("automaterStopAll")
}

// MARK: - State

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
    @Published var runningApps: [(app: NSRunningApplication, name: String)] = []
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
    private var cancellables = Set<AnyCancellable>()

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

    func toggleClicker() {
        if isClicking { stopClicker(); return }
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
        stopClicker()
        stopRecording()
        Task {
            await macroEngine.stop()
            await MainActor.run { playingMacro = false }
        }
    }

    func grabFixedPoint() {
        let loc = EventPoster.cursorLocation
        fixedX = Int(loc.x)
        fixedY = Int(loc.y)
        status = "Fixed point (\(fixedX), \(fixedY))"
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
                return (app, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func select(app: NSRunningApplication) {
        let wins = WindowScanner.windows(pid: app.processIdentifier)
        windowsOfTarget = wins
        setTarget(wins.first ?? WindowInfo(
            windowId: -1, pid: app.processIdentifier,
            ownerName: app.localizedName ?? "", bundleId: app.bundleIdentifier,
            title: "", bounds: .zero, layer: 0
        ))
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
        recordedSteps = []
        recorder.start()
        isRecording = recorder.recording
    }

    func stopRecording() {
        guard recorder.recording else { return }
        recorder.stop()
        isRecording = false
    }

    // MARK: macros

    func refreshMacros() {
        macros = Storage.listMacros()
    }

    func saveCurrentMacro() {
        currentMacro.steps = currentMacro.id.isEmpty
            ? recordedSteps : (recordedSteps.isEmpty ? currentMacro.steps : recordedSteps)
        Storage.saveMacro(currentMacro)
        refreshMacros()
        status = "Saved “\(currentMacro.name)”"
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

import Combine

// MARK: - Root view

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Automater").font(.title2).bold()
                Text("v0.1.0-swift").font(.caption).foregroundStyle(.secondary)
                Spacer()
                StatusPill(text: state.status,
                           active: state.isClicking || state.isRecording || state.playingMacro)
                if state.isClicking || state.isRecording || state.playingMacro {
                    Button("Stop all") { state.stopAll() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
            .padding([.horizontal, .top])

            TabView(selection: $tab) {
                ClickerView().tabItem { Label("Clicker", systemImage: "cursorarrow.click") }.tag(0)
                TargetPickerView().tabItem { Label("Target", systemImage: "scope") }.tag(1)
                MacrosView().tabItem { Label("Macros", systemImage: "list.bullet.rectangle") }.tag(2)
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
            }
            .padding()
        }
    }
}

struct StatusPill: View {
    let text: String
    let active: Bool
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.18) : Color.gray.opacity(0.15))
            .clipShape(Capsule())
    }
}
