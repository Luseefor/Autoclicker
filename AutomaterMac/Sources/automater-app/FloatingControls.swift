import AppKit
import SwiftUI

@MainActor
enum FloatingControls {
    private static var panel: NSPanel?

    static func toggle(state: AppState) {
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        let view = FloatingControlsView().environmentObject(state)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 118),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "Automater Controls"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private struct FloatingControlsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state.isClicking ? "Clicker running" : "Clicker ready",
                  systemImage: state.isClicking ? "play.circle.fill" : "cursorarrow.click")
                .foregroundStyle(state.isClicking ? .green : .primary)
            HStack {
                Button(state.isClicking ? "Stop" : "Start") { state.toggleClicker() }
                    .buttonStyle(.borderedProminent)
                    .tint(state.isClicking ? .red : .accentColor)
                Button("Stop All") { state.stopAll() }
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 260, height: 118, alignment: .topLeading)
    }
}
