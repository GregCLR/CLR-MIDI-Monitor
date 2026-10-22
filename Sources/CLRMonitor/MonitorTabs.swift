import SwiftUI

struct CaptureExportAction { let enabled: Bool; let perform: () -> Void }
private struct CaptureExportKey: FocusedValueKey { typealias Value = CaptureExportAction }
extension FocusedValues {
    var captureExport: CaptureExportAction? {
        get { self[CaptureExportKey.self] }
        set { self[CaptureExportKey.self] = newValue }
    }
}
struct CaptureExportCommands: Commands {
    @FocusedValue(\.captureExport) private var export
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Export Capture…") { export?.perform() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(export?.enabled != true)
        }
    }
}
struct MonitorTabs: View {
    @ObservedObject var midi: MonitorModel
    @ObservedObject var osc: OSCModel
    @State private var tab = "MIDI"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("Protocol", selection: $tab) {
                    Text("MIDI").tag("MIDI")
                    Text("OSC").tag("OSC")
                }.pickerStyle(.segmented).frame(width: 220).accessibilityLabel("Monitor protocol")
                Spacer()
                Text("MIDI \(midi.running ? "On" : "Off")").foregroundStyle(midi.running ? Color.green : Color.secondary)
                Text("OSC \(osc.running ? "On" : "Off")").foregroundStyle(osc.running ? Color.green : Color.secondary)
            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 8).background(CLR.sidebar)
            Divider().overlay(CLR.line)
            if tab == "MIDI" { MonitorView(model: midi) }
            else { OSCView(model: osc) }
        }
        .focusedSceneValue(\.captureExport, CaptureExportAction(enabled: tab == "MIDI" ? !midi.events.isEmpty : !osc.events.isEmpty, perform: { if tab == "MIDI" { midi.export() } else { osc.export() } }))
    }
}
