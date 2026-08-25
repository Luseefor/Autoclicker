import SwiftUI
import AppKit
import Combine
import AutomaterKit

// MARK: - Root

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case clicker, target, macros
    var id: Self { self }

    var title: String {
        switch self {
        case .clicker: return "Clicker"
        case .target: return "Target"
        case .macros: return "Macros"
        }
    }

    var systemImage: String {
        switch self {
        case .clicker: return "cursorarrow.click"
        case .target: return "scope"
        case .macros: return "list.bullet.rectangle"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SidebarItem = .clicker

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
            } detail: {
                detailView
                    .frame(minWidth: 560)
            }
            statusBar
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .clicker: ClickerView()
        case .target: TargetPickerView()
        case .macros: MacrosView()
        }
    }

    private var anyActive: Bool {
        state.isClicking || state.isRecording || state.playingMacro
    }

    /// Xcode-style bottom status strip.
    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(anyActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(state.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if anyActive {
                Button("Stop All") { state.stopAll() }
                    .controlSize(.small)
            }
            Button("Controls") { state.toggleFloatingControls() }
                .controlSize(.small)
                .help("Show or hide the always-on-top start and stop controls")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Clicker tab

struct ClickerView: View {
    @EnvironmentObject var state: AppState
    @State private var intervalUnit: IntervalUnit = .ms

    enum IntervalUnit: String, CaseIterable, Identifiable {
        case ms, seconds, minutes
        var id: Self { self }

        var label: String {
            switch self {
            case .ms: return "ms"
            case .seconds: return "sec"
            case .minutes: return "min"
            }
        }

        var msPerUnit: Int {
            switch self {
            case .ms: return 1
            case .seconds: return 1_000
            case .minutes: return 60_000
            }
        }

        var step: Int {
            switch self {
            case .ms: return 25
            case .seconds: return 1
            case .minutes: return 1
            }
        }

        var maxValue: Int {
            switch self {
            case .ms: return 60_000
            case .seconds: return 3_600
            case .minutes: return 1_440
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 24) {
                Form {
                    timingSection
                    mouseSection
                    modeSection
                    multipointSection
                    deliverySection
                    Section { startButton }
                }
                .formStyle(.grouped)
                .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)

                if geo.size.width >= 1080 {
                    runSummary
                        .frame(width: 280)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: sections

    private var timingSection: some View {
        Section("Timing") {
            row("Interval") {
                HStack(spacing: 12) {
                    TextField("", value: intervalValueBinding, format: .number)
                        .frame(width: 72)
                        .accessibilityLabel("Click interval")
                    Stepper("", value: intervalValueBinding,
                            in: 1...intervalUnit.maxValue, step: intervalUnit.step)
                        .labelsHidden()
                        .fixedSize()
                    Picker("Unit", selection: $intervalUnit) {
                        ForEach(IntervalUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 84)
                }
                Spacer()
            }
            row("Jitter") {
                HStack(spacing: 12) {
                    TextField("", value: jitterBinding, format: .number)
                        .frame(width: 72)
                        .accessibilityLabel("Click interval jitter in milliseconds")
                    Stepper("", value: jitterBinding, in: 0...5_000)
                        .labelsHidden()
                        .fixedSize()
                    Text("± ms")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            row("Repeat") {
                HStack(spacing: 12) {
                    TextField("", value: repeatBinding, format: .number)
                        .frame(width: 72)
                        .accessibilityLabel("Repeat count; zero means continuous")
                    Stepper("", value: repeatBinding, in: 0...1_000_000)
                        .labelsHidden()
                        .fixedSize()
                    Text(state.repeatCount == 0 ? "Infinite — until stopped" : "clicks")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var mouseSection: some View {
        Section("Mouse") {
            row("Button") {
                Picker("Button", selection: $state.button) {
                    ForEach(MouseButton.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Spacer()
            }
            row("Click Type") {
                Picker("Click Type", selection: $state.kind) {
                    ForEach(ClickKind.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Spacer()
            }
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $state.mode) {
                Text("Current Cursor").tag(ClickerConfig.Mode.currentCursor)
                Text("Fixed Point").tag(ClickerConfig.Mode.fixedPoint)
                Text("Multi-Point").tag(ClickerConfig.Mode.multipoint)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if state.mode == .fixedPoint {
                row("Fixed Point") {
                    HStack(spacing: 8) {
                        TextField("X", value: $state.fixedX, format: .number)
                            .frame(width: 72)
                            .accessibilityLabel("Fixed point horizontal position")
                        TextField("Y", value: $state.fixedY, format: .number)
                            .frame(width: 72)
                            .accessibilityLabel("Fixed point vertical position")
                        Button {
                            state.toggleFixedPointCapture()
                        } label: {
                            Label(state.isCapturingFixedPoint
                                  ? "Click target…" : "Grab Cursor",
                                  systemImage: state.isCapturingFixedPoint
                                  ? "scope" : "cursorarrow.click")
                        }
                            .tint(state.isCapturingFixedPoint ? .red : .accentColor)
                            .help("Arm this and click the real target point — or hover + ⌃⌥G. A laser marker shows the spot.")
                            Button("Clear", role: .destructive) {
                                state.clearFixedPoint()
                            }
                            .disabled(!state.hasFixedPoint)
                            .help("Hide the laser marker")
                    }
                    Spacer()
                }
            }
        }
    }

    private var multipointSection: some View {
        Section("Multi-Points") {
            if state.multipoints.isEmpty {
                Text(state.isPicking
                     ? "Click anywhere to capture points — Esc or Finish when done."
                     : "Hover and press ⌃⌥G, click “Pick Points” and click around, or use Add at Cursor.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(state.multipoints.enumerated()), id: \.offset) { i, p in
                    row("Point \(i + 1)") {
                        Text(p.coordSpace == .window ? "window" : "screen")
                            + Text(" (\(p.x ?? 0), \(p.y ?? 0))")
                        Spacer()
                    }
                    .contextMenu {
                        Button("Remove Point", role: .destructive) {
                            state.multipoints.remove(at: i)
                        }
                    }
                }
            }
            HStack {
                Button {
                    state.togglePicking()
                } label: {
                    Label(state.isPicking ? "Finish Picking" : "Pick Points",
                          systemImage: state.isPicking ? "checkmark.circle.fill" : "target")
                }
                .tint(state.isPicking ? .red : .accentColor)
                .disabled(state.isRecording || state.isClicking)
                Button("Add at Cursor") { state.addPointAtCursor() }
                    .help("Or hover anywhere and press ⌃⌥G")
                Button("Clear All", role: .destructive) { state.multipoints.removeAll() }
                    .disabled(state.multipoints.isEmpty)
                Spacer()
                Text("\(state.multipoints.count) point\(state.multipoints.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deliverySection: some View {
        Section {
            Toggle("Click target app in the background (pointer stays put)",
                   isOn: $state.backgroundToApp)
                .help("Uses supported macOS background delivery. Some apps may require foreground clicking.")
            Picker("Delivery", selection: $state.deliveryMode) {
                Text("Smart background (AX + events)").tag(ClickerConfig.DeliveryMode.accessibility)
                Text("Synthetic events only").tag(ClickerConfig.DeliveryMode.events)
            }
            .pickerStyle(.radioGroup)
            .disabled(!state.backgroundToApp)
            HStack(spacing: 8) {
                Image(systemName: compatibilityIcon)
                    .foregroundStyle(compatibilityColor)
                Text(state.backgroundCompatibility.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Check Compatibility") {
                    state.checkBackgroundCompatibility()
                }
                .disabled(state.targetWindow == nil)
                .help("Checks whether the selected app exposes a supported macOS background-delivery path. It does not send a click.")
            }
            Text(state.backgroundCompatibility.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Delivery")
        } footer: {
            Text(targetSummary)
        }
    }

    private var compatibilityIcon: String {
        switch state.backgroundCompatibility {
        case .likely: return "checkmark.circle.fill"
        case .syntheticOnly: return "exclamationmark.triangle.fill"
        case .foregroundRecommended: return "hand.raised.fill"
        case .noTarget: return "questionmark.circle"
        }
    }

    private var compatibilityColor: Color {
        switch state.backgroundCompatibility {
        case .likely: return .green
        case .syntheticOnly: return .orange
        case .foregroundRecommended: return .red
        case .noTarget: return .secondary
        }
    }

    private var runSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ready to run", systemImage: "cursorarrow.click.2")
                .font(.headline)
            Divider()
            summaryRow("Interval", "\(state.intervalTotalMs) ms")
            summaryRow("Click", "\(state.button.rawValue.capitalized) · \(state.kind.rawValue)")
            summaryRow("Mode", modeLabel)
            summaryRow("Repeat", state.repeatCount == 0 ? "Until stopped" : "\(state.repeatCount) clicks")
            Divider()
            Label(state.backgroundCompatibility.title, systemImage: compatibilityIcon)
                .font(.callout.weight(.medium))
                .foregroundStyle(compatibilityColor)
            Text("Use ⌘⇧A to start or stop clicking. Stop All is always available in the status bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Pin Controls on Top") { state.toggleFloatingControls() }
                .buttonStyle(.bordered)
                .help("Shows a small start/stop panel above other windows and Spaces.")
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modeLabel: String {
        switch state.mode {
        case .currentCursor: return "Current cursor"
        case .fixedPoint: return "Fixed point"
        case .multipoint: return "\(state.multipoints.count) points"
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    // MARK: pieces

    /// Interval edited as one value + unit; the h/m/s/ms settings buckets
    /// stay the source of truth via `intervalTotalMs`.
    private var intervalValueBinding: Binding<Int> {
        Binding(
            get: { max(1, state.intervalTotalMs / intervalUnit.msPerUnit) },
            set: { state.intervalTotalMs = min($0, intervalUnit.maxValue) * intervalUnit.msPerUnit }
        )
    }

    /// Repeat count: typeable AND steppable, clamped to 0...1M (0 = ∞).
    private var repeatBinding: Binding<Int> {
        Binding(
            get: { state.repeatCount },
            set: { state.repeatCount = min(max($0, 0), 1_000_000) }
        )
    }

    /// Jitter in ms: typeable AND steppable, clamped to 0...5000.
    private var jitterBinding: Binding<Int> {
        Binding(
            get: { state.jitterMs },
            set: { state.jitterMs = min(max($0, 0), 5_000) }
        )
    }

    /// Form row with a fixed-width leading label that can never compress
    /// or clip, followed by a single control.
    private func row<Content: View>(_ label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .frame(width: 140, alignment: .leading)
            HStack(spacing: 14) { content() }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var targetSummary: String {
        guard state.backgroundToApp else {
            return "Foreground delivery — clicks land wherever the pointer is."
        }
        return state.targetWindow.map {
            "Targeting \($0.ownerName)" + ($0.title.isEmpty ? "." : " — \($0.title).")
        } ?? "No target selected. Pick an app in the Target section for background delivery."
    }

    private var startButton: some View {
        Button {
            state.toggleClicker()
        } label: {
            Label(state.isClicking ? "Stop Clicking" : "Start Clicking",
                  systemImage: state.isClicking ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(state.isClicking ? .red : .accentColor)
        .disabled(state.isPicking)
    }
}

// MARK: - Target tab

/// Target picker: two adaptive lists (apps → windows). Lists with custom
/// rows handle narrow panes gracefully — no columns to crush.
struct TargetPickerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GeometryReader { geo in
            // Below ~700pt of detail width the two panes stop fitting
            // side-by-side — stack them instead of clipping.
            let compact = geo.size.width < 700
            VStack(alignment: .leading, spacing: 12) {
                currentTargetBanner
                if compact {
                    appPane
                        .padding(.horizontal, 12)
                        .frame(height: 240)
                    Divider()
                    windowPane
                        .padding(.horizontal, 12)
                } else {
                    HSplitView {
                        appPane
                            .padding(12)
                            .frame(minWidth: 280, idealWidth: 330)
                            .layoutPriority(1)
                        windowPane
                            .padding(12)
                            .frame(minWidth: 300, idealWidth: 420)
                    }
                }
                Text("Click an app, then one of its windows. The ◎ mark shows the active target — background clicks are delivered there without touching your pointer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    private var appSelection: Binding<Int32?> {
        Binding(
            get: { state.selectedAppID },
            set: { state.selectApp(id: $0) }
        )
    }

    private var windowSelection: Binding<Int?> {
        Binding(
            get: { state.selectedWindowID },
            set: { state.selectWindow(id: $0) }
        )
    }

    private var appPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Running Apps").font(.headline)
                Spacer()
                Text("\(state.runningApps.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            List(selection: appSelection) {
                ForEach(state.runningApps) { app in
                    AppListRow(
                        app: app,
                        isTarget: state.targetWindow?.pid == app.id
                    )
                    .tag(app.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if state.runningApps.isEmpty {
                    Text("No apps — click Refresh")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Refresh") { state.refreshApps() }
                .controlSize(.small)
        }
    }

    private var windowPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Windows of Target").font(.headline)
            if state.windowsOfTarget.isEmpty {
                GroupBox {
                    VStack(spacing: 6) {
                        Image(systemName: state.selectedAppID == nil ? "scope" : "rectangle.dashed")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(state.selectedAppID == nil
                             ? "Select an app on the left"
                             : "No scannable windows — app-level targeting will be used")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                Spacer()
            } else {
                List(selection: windowSelection) {
                    ForEach(state.windowsOfTarget) { w in
                        WindowListRow(
                            window: w,
                            isTarget: state.targetWindow?.windowId == w.windowId
                        )
                        .tag(w.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var currentTargetBanner: some View {
        HStack(spacing: 10) {
            if let t = state.targetWindow {
                if let app = NSRunningApplication(processIdentifier: t.pid),
                   let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.ownerName + (t.title.isEmpty ? "" : " — \(t.title)"))
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("pid \(t.pid) · wid \(t.windowId)" + (t.isOnScreen ? "" : " · minimized/off-Space"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label(state.backgroundCompatibility.title,
                          systemImage: compatibilityIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(compatibilityColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No target selected").font(.headline)
                    Text("Pick an app below to begin")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.targetWindow != nil {
                Button("Clear", role: .destructive) {
                    state.targetWindow = nil
                    state.selectedAppID = nil
                    state.selectedWindowID = nil
                    state.windowsOfTarget = []
                    state.status = "Target cleared"
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var compatibilityIcon: String {
        switch state.backgroundCompatibility {
        case .likely: return "checkmark.circle.fill"
        case .syntheticOnly: return "exclamationmark.triangle.fill"
        case .foregroundRecommended: return "hand.raised.fill"
        case .noTarget: return "questionmark.circle"
        }
    }

    private var compatibilityColor: Color {
        switch state.backgroundCompatibility {
        case .likely: return .green
        case .syntheticOnly: return .orange
        case .foregroundRecommended: return .red
        case .noTarget: return .secondary
        }
    }
}

private struct AppListRow: View {
    let app: RunningApp
    let isTarget: Bool

    var body: some View {
        HStack(spacing: 9) {
            if let icon = app.app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.app.bundleIdentifier ?? "pid \(app.app.processIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if isTarget {
                Image(systemName: "target")
                    .foregroundStyle(Color.accentColor)
                    .help("Current target app")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

private struct WindowListRow: View {
    let window: WindowInfo
    let isTarget: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isTarget ? "target" : "circle.dashed")
                .foregroundStyle(isTarget ? Color.accentColor : Color.secondary.opacity(0.35))
                .help(isTarget ? "Active target" : "Click to target this window")
            VStack(alignment: .leading, spacing: 1) {
                Text(window.title.isEmpty ? "(untitled)" : window.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text("\(Int(window.bounds.width))×\(Int(window.bounds.height))")
                    Text("·")
                    Text(window.isOnScreen ? "On Screen" : "Minimized / Off-Space")
                        .foregroundStyle(window.isOnScreen ? Color.secondary : Color.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Macros tab

struct MacrosView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Macros").font(.headline)
                Table(state.macros,
                      selection: Binding(
                        get: { state.selectedMacroID },
                        set: { state.selectMacro(id: $0) }
                      )) {
                    TableColumn("Name") { m in Text(m.name) }
                    TableColumn("Steps") { m in
                        Text("\(m.steps.count)").foregroundStyle(.secondary)
                    }
                    TableColumn("Loop") { m in
                        Text(m.loopCount == 0 ? "∞" : "\(m.loopCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button {
                        state.newMacro()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New macro")
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Delete selected macro")
                    .disabled(state.currentMacro.id.isEmpty)
                    .confirmationDialog(
                        "Delete Macro",
                        isPresented: $confirmDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete “\(state.currentMacro.name)”", role: .destructive) {
                            state.deleteCurrentMacro()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently removes the saved macro file.")
                    }
                    Spacer()
                    Button("Save Current") { state.saveCurrentMacro() }
                }
            }
            .padding().frame(minWidth: 260, idealWidth: 320)

            VStack(alignment: .leading, spacing: 8) {
                Form {
                    Section("Macro") {
                        TextField("Name", text: $state.currentMacro.name)
                        HStack {
                            Text("Loops").frame(width: 64, alignment: .leading)
                            TextField("", value: $state.currentMacro.loopCount,
                                      format: .number)
                                .frame(width: 54)
                            Stepper("", value: $state.currentMacro.loopCount, in: 0...10_000)
                                .labelsHidden()
                            Text(state.currentMacro.loopCount == 0 ? "Runs continuously" : "times")
                                .foregroundStyle(.secondary)
                        }
                        Text("Set the count to 0 to repeat until stopped.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Steps") {
                        stepsList
                        controlsRow
                    }
                }
                .formStyle(.grouped)
            }
            .padding().frame(minWidth: 420, idealWidth: 480)
        }
        .onAppear { state.refreshMacros() }
    }

    private var stepsList: some View {
        Group {
            if state.displaySteps.isEmpty {
                Text("Nothing recorded. Press Record or add a click below.")
                    .foregroundStyle(.secondary)
            } else {
                List(Array(state.displaySteps.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Text(stepLabel(s))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            state.deleteStep(at: i)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this step")
                        .accessibilityLabel("Delete step \(i + 1)")
                    }
                    .contextMenu {
                        Button("Delete Step", role: .destructive) {
                            state.deleteStep(at: i)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
            }
        }
    }

    private var controlsRow: some View {
        VStack(spacing: 10) {
            Toggle("Use recorded steps as macro steps", isOn: $state.useRecordedForPlay)
            HStack {
                Button {
                    state.toggleRecording()
                } label: {
                    Label(state.isRecording ? "Stop Recording" : "Record",
                          systemImage: state.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .tint(state.isRecording ? .red : .accentColor)
                Button("Clear Recording") {
                    state.recordedSteps = []
                    state.recorder.clear()
                }
                .disabled(state.recordedSteps.isEmpty)
                Button("Add Click at Cursor") { state.appendClickStepAtCursor() }
                Spacer()
                playButton
            }
        }
        .font(.callout)
    }

    private var playButton: some View {
        let macro = state.playableMacro()
        return Button {
            state.play(macro: macro)
        } label: {
            Label("Play “\(state.currentMacro.name)”", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(state.playingMacro || macro.steps.isEmpty)
    }

    private func stepLabel(_ s: MacroStep) -> String {
        let secs = s.holdMs > 0 ? String(format: "%.1fs", Double(s.holdMs) / 1000) : nil
        switch s.type {
        case "click":
            return "click (\(s.x ?? 0),\(s.y ?? 0)) \(s.button ?? "left") \(s.clickKind)"
        case "hold":
            return "hold (\(s.x ?? 0),\(s.y ?? 0)) \(s.button ?? "left") \(secs ?? "")"
        case "drag":
            return "drag (\(s.x ?? 0),\(s.y ?? 0)) → (\(s.endX ?? 0),\(s.endY ?? 0)) \(s.button ?? "left")"
        case "key":
            return "key \(s.key ?? "?")" + (secs.map { " · hold \($0)" } ?? "")
        case "type":
            return "type \"\((s.text ?? "").prefix(24))\""
        case "delay":
            return "delay \(s.delayMs)ms"
        case "scroll":
            let amount = secs ?? "\(s.dy ?? 0) lines"
            return "scroll \(scrollArrow(s)) \(amount)"
        case "swipe":
            return "swipe \(swipeArrow(s)) · system shortcut"
        default:
            return s.type
        }
    }

    private func scrollArrow(_ s: MacroStep) -> String {
        if (s.dy ?? 0) < 0 { return "↑" }
        if (s.dy ?? 0) > 0 { return "↓" }
        if (s.dx ?? 0) < 0 { return "←" }
        if (s.dx ?? 0) > 0 { return "→" }
        return "·"
    }

    private func swipeArrow(_ s: MacroStep) -> String {
        if (s.dx ?? 0) < 0 { return "← (previous Space)" }
        if (s.dx ?? 0) > 0 { return "→ (next Space)" }
        if (s.dy ?? 0) < 0 { return "↑ (Mission Control)" }
        if (s.dy ?? 0) > 0 { return "↓ (App Exposé)" }
        return "·"
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

    /// Removes one step from whichever source the list is showing
    /// (live recording or the saved macro) — other steps stay intact.
    func deleteStep(at index: Int) {
        if useRecordedForPlay && !recordedSteps.isEmpty {
            guard recordedSteps.indices.contains(index) else { return }
            recordedSteps.remove(at: index)
        } else {
            guard currentMacro.steps.indices.contains(index) else { return }
            currentMacro.steps.remove(at: index)
        }
    }

    func playableMacro() -> Macro {
        var m = currentMacro
        if useRecordedForPlay && !recordedSteps.isEmpty {
            m.steps = recordedSteps
        }
        return m
    }
}

// MARK: - Settings window (native ⌘, scene)

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var axTrusted = AXBridge.isTrustedForAccessibility

    /// TCC decisions are cached per-process: after the user grants
    /// Accessibility, the running app still sees "not trusted" until it
    /// relaunches. Poll so we flip the moment the system allows it, and
    /// offer a restart when it can't flip live.
    private let trustPoll = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        Form {
            Section("Permissions") {
                HStack(spacing: 12) {
                    Text("Accessibility").frame(width: 110, alignment: .leading)
                    Label(axTrusted ? "Granted" : "Required",
                          systemImage: axTrusted ? "checkmark.shield" : "exclamationmark.shield.fill")
                        .foregroundStyle(axTrusted ? Color.green : Color.orange)
                    Spacer()
                }
                if !axTrusted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Click Reset Permission Entries — clears stale grants from older builds.")
                        Text("2. Click Grant… — System Settings opens.")
                        Text("3. Add the current Automater (drag from Reveal in Finder), then toggle it on.")
                        Text("4. Click Restart & Apply — the grant only takes effect on relaunch.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                    if !axTrusted {
                        Button("Grant…") { AXBridge.requestAccessibilityPrompt() }
                        Button("Reset Permission Entries") { Self.resetTCCEntries() }
                            .help("Runs tccutil reset for Automater — wipes stale entries")
                    }
                    Button("Restart & Apply") { Self.restartApp() }
                    Spacer()
                    Button("Recheck Now") {
                        axTrusted = AXBridge.isTrustedForAccessibility
                    }
                }
            }

            Section("Global Hotkeys") {
                ForEach(HotkeyCoordinator.bindings, id: \.setting) { b in
                    HotkeyRow(setting: b.setting, label: b.label,
                              binding: HotkeyCoordinator.binding(for: b.setting))
                }
                Text("Click a shortcut to rebind it. Global — works in any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Folder").frame(width: 96, alignment: .leading)
                    Text(Storage.appDir.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.appDir])
                    }
                    Button("Reveal Diagnostics") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.diagnosticsURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 440)
        .onReceive(trustPoll) { _ in
            if !axTrusted {
                axTrusted = AXBridge.isTrustedForAccessibility
            }
        }
    }

    /// Wipes every TCC entry for this bundle id. Stale entries from earlier
    /// ad-hoc builds shadow fresh ones (System Settings dedupes by name), so
    /// a reset is the only reliable way to re-grant after identity changes.
    static func resetTCCEntries() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.luseefor.automater"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
    }

    /// Spawns a fresh instance, then quits this one so the new process
    /// re-evaluates TCC with clean state.
    static func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Hotkey keycaps + rebinding

/// One keycap badge ("⌃", "⌥", "A").
struct KeyCap: View {
    let symbol: String
    var isModifier: Bool = false

    var body: some View {
        Text(symbol)
            .font(.system(isModifier ? .footnote : .callout, design: .rounded).weight(.medium))
            .frame(minWidth: isModifier ? 22 : 24, minHeight: 24)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 0.6, y: 1.2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.7)
                    )
            )
    }
}

/// "ctrl+alt+a" → ordered keycap symbols.
@ViewBuilder
func hotkeyCaps(_ binding: String) -> some View {
    let parts = binding.split(separator: "+")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let symbols: [(String, Bool)] = parts.map { part in
        switch part {
        case "ctrl", "control", "right_ctrl": return ("⌃", true)
        case "alt", "opt", "option", "right_alt": return ("⌥", true)
        case "shift", "right_shift": return ("⇧", true)
        case "cmd", "command", "right_cmd": return ("⌘", true)
        default:
            let pretty = part.count == 1 ? part.uppercased() : part.replacingOccurrences(of: "_", with: " ")
            return (pretty, false)
        }
    }
    HStack(spacing: 3) {
        ForEach(Array(symbols.enumerated()), id: \.offset) { _, cap in
            KeyCap(symbol: cap.0, isModifier: cap.1)
        }
    }
}

struct HotkeyRow: View {
    let setting: String
    let label: String
    let binding: String

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 150, alignment: .leading)
            if recording {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Press new shortcut — Esc to cancel")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    startRecording()
                } label: {
                    hotkeyCaps(binding)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to rebind")
            }
            Spacer()
        }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keycode = event.keyCode
            if keycode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            guard KeyCodeMap.name(for: keycode) != nil,
                  !KeyCodeMap.isModifier(name: KeyCodeMap.name(for: keycode) ?? "") else {
                return nil // swallow lone modifiers while recording
            }
            var mods: [String] = []
            if event.modifierFlags.contains(.control) { mods.append("ctrl") }
            if event.modifierFlags.contains(.option) { mods.append("alt") }
            if event.modifierFlags.contains(.shift) { mods.append("shift") }
            if event.modifierFlags.contains(.command) { mods.append("cmd") }
            let keyName = KeyCodeMap.name(for: keycode) ?? ""
            let combo = (mods + [keyName]).joined(separator: "+")
            stopRecording()
            HotkeyCoordinator.rebind(setting: setting, to: combo)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
