import SwiftUI
import AppKit
import AutomaterKit

// MARK: - Clicker tab

struct ClickerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                intervalRow
                buttonRow
                modeRow
                if state.mode == .fixedPoint { fixedRow }
                repeatRow
                backgroundRow
                Spacer()
                startRow
            }
            .padding()
            .frame(minWidth: 460)

            multipointPane
                .frame(minWidth: 320)
        }
    }

    private var intervalRow: some View {
        HStack {
            Text("Interval").frame(width: 70, alignment: .leading)
            Stepper("\(state.intervalH) h", onIncrement: { state.intervalH += 1 }, onDecrement: { state.intervalH = max(0, state.intervalH - 1) }).frame(width: 84)
            Stepper("\(state.intervalM) m", onIncrement: { state.intervalM += 1 }, onDecrement: { state.intervalM = max(0, state.intervalM - 1) }).frame(width: 84)
            Stepper("\(state.intervalS) s", onIncrement: { state.intervalS += 1 }, onDecrement: { state.intervalS = max(0, state.intervalS - 1) }).frame(width: 84)
            Stepper("\(state.intervalMs) ms", onIncrement: { state.intervalMs = min(999, state.intervalMs + 25) }, onDecrement: { state.intervalMs = max(0, state.intervalMs - 25) }).frame(width: 104)
        }
    }

    private var buttonRow: some View {
        HStack {
            Text("Button").frame(width: 70, alignment: .leading)
            Picker("", selection: $state.button) {
                ForEach(MouseButton.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 100)
            Text("Click type")
            Picker("", selection: $state.kind) {
                ForEach(ClickKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 100)
            Spacer()
        }
    }

    private var modeRow: some View {
        HStack {
            Text("Mode").frame(width: 70, alignment: .leading)
            Picker("", selection: $state.mode) {
                Text("Current cursor").tag(ClickerConfig.Mode.currentCursor)
                Text("Fixed point").tag(ClickerConfig.Mode.fixedPoint)
                Text("Multi-point").tag(ClickerConfig.Mode.multipoint)
            }
            .pickerStyle(.segmented)
            .frame(width: 380)
            Spacer()
        }
    }

    private var fixedRow: some View {
        HStack {
            Text("Fixed X/Y").frame(width: 70, alignment: .leading)
            TextField("X", value: $state.fixedX, format: .number).frame(width: 70)
            TextField("Y", value: $state.fixedY, format: .number).frame(width: 70)
            Button("Grab cursor") { state.grabFixedPoint() }
            Spacer()
        }
    }

    private var repeatRow: some View {
        HStack {
            Text("Repeat").frame(width: 70, alignment: .leading)
            Stepper(value: $state.repeatCount, in: 0...1_000_000) {
                Text(state.repeatCount == 0 ? "Infinite" : "\(state.repeatCount)")
            }.frame(width: 130)
            Text("Jitter ±")
            Stepper(value: $state.jitterMs, in: 0...5000) {
                Text("\(state.jitterMs) ms")
            }.frame(width: 110)
            Spacer()
        }
    }

    private var backgroundRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Click target app in the background (pointer stays put)", isOn: $state.backgroundToApp)
            Picker("Delivery", selection: $state.deliveryMode) {
                Text("Accessibility (AXPress)").tag(ClickerConfig.DeliveryMode.accessibility)
                Text("Synthetic events").tag(ClickerConfig.DeliveryMode.events)
            }
            .pickerStyle(.radioGroup)
            .disabled(!state.backgroundToApp)
            Text(state.targetWindow.map {
                "Target: \($0.ownerName)" + ($0.title.isEmpty ? "" : " — \($0.title)")
            } ?? "No target selected (Target tab)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var startRow: some View {
        Button(state.isClicking ? "Stop clicking" : "Start clicking") {
            state.toggleClicker()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var multipointPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multi-points").font(.headline)
            List {
                ForEach(Array(state.multipoints.enumerated()), id: \.offset) { i, p in
                    Text("\(i + 1). \(p.coordSpace == .window ? "window" : "screen") (\(p.x ?? 0), \(p.y ?? 0))")
                }
                .onDelete { state.removeSelectedPoints(at: $0) }
            }
            .listStyle(.inset)
            HStack {
                Button("Add at cursor") { state.addPointAtCursor() }
                Button("Clear") { state.multipoints.removeAll() }
                Spacer()
                Text("\(state.multipoints.count) points")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Target tab

struct TargetPickerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                header("Running apps", count: state.runningApps.count)
                List(state.runningApps, id: \.app.processIdentifier, selection: Binding(
                    get: { state.selectedAppID },
                    set: { state.selectApp(id: $0) }
                )) { row in
                    HStack(spacing: 10) {
                        if let icon = row.app.icon {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        }
                        VStack(alignment: .leading) {
                            Text(row.name)
                            Text(row.app.bundleIdentifier ?? "pid \(row.app.processIdentifier)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.select(app: row.app) }
                }
                .listStyle(.inset)
                HStack {
                    Button("Refresh") { state.refreshApps() }
                    Spacer()
                }
            }
            .padding().frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 8) {
                header("Windows of target", count: state.windowsOfTarget.count)
                List(state.windowsOfTarget, id: \.windowId, selection: Binding(
                    get: { state.selectedWindowID },
                    set: { state.selectWindow(id: $0) }
                )) { w in
                    VStack(alignment: .leading) {
                        Text(w.title.isEmpty ? "(untitled)" : w.title)
                        Text("\(Int(w.bounds.width))×\(Int(w.bounds.height)) · wid \(w.windowId)\(w.layer != 0 ? " · off-screen" : "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.setTarget(w) }
                }
                .listStyle(.inset)
            }
            .padding().frame(minWidth: 300)
        }
    }

    @ViewBuilder private func header(_ t: String, count: Int) -> some View {
        HStack {
            Text(t).font(.headline)
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Macros tab

struct MacrosView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved macros").font(.headline)
                List(state.macros, id: \.id, selection: Binding(
                        get: { state.selectedMacroID },
                        set: { state.selectMacro(id: $0) }
                    )) { m in
                    VStack(alignment: .leading) {
                        Text(m.name)
                        Text("\(m.steps.count) steps · loop \(m.loopCount == 0 ? "∞" : String(m.loopCount))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.loadMacro(m) }
                }
                .listStyle(.inset)
                HStack {
                    Button("New") { state.newMacro() }
                    Button("Delete") { state.deleteCurrentMacro() }
                    Spacer()
                    Button("Save current") { state.saveCurrentMacro() }
                }
            }
            .padding().frame(minWidth: 240)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Macro name", text: $state.currentMacro.name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Stepper(value: $state.currentMacro.loopCount, in: 0...10_000) {
                        Text(state.currentMacro.loopCount == 0 ? "Loops ∞" : "Loops \(state.currentMacro.loopCount)")
                    }
                    Spacer()
                }
                stepList
                controls
            }
            .padding().frame(minWidth: 420)
        }
        .onAppear { state.refreshMacros() }
    }

    private var stepList: some View {
        GroupBox("Steps") {
            List {
                ForEach(Array(state.displaySteps.enumerated()), id: \.offset) { _, s in
                    Text(stepLabel(s)).font(.system(.caption, design: .monospaced))
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 160)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Toggle("Use recorded steps as macro steps", isOn: $state.useRecordedForPlay)
            HStack {
                Button(state.isRecording ? "⏹ Stop recording" : "● Record") { state.toggleRecording() }
                    .tint(state.isRecording ? .red : .accentColor)
                Button("Clear recording") { state.recordedSteps = []; state.recorder.clear() }
                Button("Add click at cursor") { state.appendClickStepAtCursor() }
                Spacer()
                Button("▶ Play “\(state.currentMacro.name)”") {
                    let m = state.playableMacro()
                    state.play(macro: m)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.playingMacro || state.playableMacro().steps.isEmpty)
            }
        }
    }

    private func stepLabel(_ s: MacroStep) -> String {
        switch s.type {
        case "click": return "click (\(s.x ?? 0),\(s.y ?? 0)) \(s.button ?? "left") \(s.clickKind)"
        case "key": return "key \(s.key ?? "?")"
        case "type": return "type \"\((s.text ?? "").prefix(24))\""
        case "delay": return "delay \(s.delayMs)ms"
        default: return s.type
        }
    }
}

extension AppState {
    var displaySteps: [MacroStep] {
        useRecordedForPlay && !recordedSteps.isEmpty ? recordedSteps : currentMacro.steps
    }

    func loadMacro(_ m: Macro) {
        currentMacro = m
        recordedSteps = []
        status = "Loaded “\(m.name)”"
    }

    func appendClickStepAtCursor() {
        let loc = EventPoster.cursorLocation
        recordedSteps.append(MacroStep(type: "click", x: Int(loc.x), y: Int(loc.y)))
        recorder.onSteps?(recordedSteps)
    }

    func playableMacro() -> Macro {
        var m = currentMacro
        if useRecordedForPlay && !recordedSteps.isEmpty {
            m.steps = recordedSteps
        }
        return m
    }
}

// MARK: - Settings tab

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var axTrusted = AXBridge.isTrustedForAccessibility

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Permissions") {
                HStack {
                    Label(axTrusted ? "Accessibility granted" : "Accessibility required",
                          systemImage: axTrusted ? "checkmark.shield" : "exclamationmark.shield.fill")
                        .foregroundStyle(axTrusted ? Color.green : Color.orange)
                    Spacer()
                    if !axTrusted {
                        Button("Grant…") { AXBridge.requestAccessibilityPrompt() }
                    }
                    Button("Recheck") { axTrusted = AXBridge.isTrustedForAccessibility }
                }
                Text("Needed for clicking, recording and hotkeys. Enable the host app (Terminal or Automater.app) in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Global hotkeys") {
                Text("⌃⌥A toggle clicker · ⌃⌥R record · ⌃⌥S stop all")
                    .font(.system(.body, design: .monospaced))
            }
            GroupBox("Storage") {
                Text(Storage.appDir.path).font(.caption)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding()
    }
}
