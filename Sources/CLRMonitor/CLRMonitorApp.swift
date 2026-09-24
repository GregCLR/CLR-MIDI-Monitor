import SwiftUI
import AppKit
import MIDICore

private enum CLR {
    static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "CLRMIDIMonitor_CLRMonitor", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return .module
    }()
    static let amber = Color(red: 0.941, green: 0.639, blue: 0.145)
    static let sidebar = Color(white: 0.085)
    static let line = Color.white.opacity(0.15)
    static let rowFont = Font.system(size: 13, design: .monospaced)
}

@main
struct CLRMonitorApp: App {
    @StateObject private var model: MonitorModel
    private let instanceLock: InstanceLock

    init() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("CLR MIDI Monitor", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let lock = try InstanceLock(path: folder.appendingPathComponent("instance.lock").path) else {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.clr.midimonitor")
                    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                    .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                exit(0)
            }
            instanceLock = lock
            _model = StateObject(wrappedValue: MonitorModel())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to start CLR MIDI Monitor"
            alert.informativeText = "The app could not establish its single-instance lock. No MIDI capture was started.\n\n\(error.localizedDescription)"
            alert.runModal()
            exit(1)
        }
    }
    var body: some Scene {
        WindowGroup("CLR MIDI Monitor") {
            MonitorView(model: model).preferredColorScheme(.dark)
        }.defaultSize(width: 1380, height: 820)
            .commands {
                MonitorHelpCommands()
                CommandGroup(replacing: .saveItem) {
                    Button("Export Capture…") { model.export() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        .disabled(model.events.isEmpty)
                }
            }
        Window("CLR MIDI Monitor Help", id: "user-guide") {
            ManualView().frame(minWidth: 600, minHeight: 500)
        }.defaultSize(width: 900, height: 760)
    }
}

private struct MonitoringSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 5) {
                    Text(configuration.isOn ? "On" : "Off").font(.system(size: 12, weight: .medium)).frame(width: 24)
                    Capsule().fill(configuration.isOn ? Color.green : Color.red)
                        .frame(width: 42, height: 24)
                        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                            Circle().fill(.white).frame(width: 18, height: 18).padding(3)
                        }
                }
            }.buttonStyle(.plain).accessibilityLabel("Monitoring").accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { sidebarVisible.toggle() } label: {
                    Label("Options", systemImage: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(sidebarVisible ? "Options — Hide sidebar" : "Options — Show sidebar")
                    .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                    .frame(width: sidebarVisible ? 301 : 128, alignment: .leading)
                HStack(spacing: 18) {
                    Image(nsImage: CLR.resources.url(forResource: "clr-logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSImage())
                        .resizable().scaledToFit().frame(width: 76, height: 36).accessibilityLabel("CLR")
                    Text("MIDI MONITOR").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Toggle("Monitoring", isOn: Binding(get: { model.running }, set: { if $0 != model.running { model.toggleCapture() } }))
                        .toggleStyle(MonitoringSwitch())
                    Button("Export") { model.export() }.disabled(model.events.isEmpty)
                }.padding(.leading, 16).padding(.trailing, 20)
            }.padding(.vertical, 14)
            Divider().overlay(CLR.line)
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar.frame(width: 300)
                    Rectangle().fill(CLR.line).frame(width: 1)
                }
                stream.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = model.error {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button("Dismiss") { model.error = nil } }.padding(12)
            }
        }.background(Color(white: 0.035)).tint(CLR.amber).frame(minWidth: 1120, minHeight: 680)
    }
    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(CLR.amber)
    }
    private func portHeading(_ label: String, inputs: Bool) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            Toggle("All", isOn: Binding(get: { model.allPortsSelected(inputs: inputs) }, set: { model.setAllPorts($0, inputs: inputs) }))
                .toggleStyle(.checkbox)
                .accessibilityLabel(inputs ? "All inputs" : "All outputs")
                .disabled(!model.endpoints.contains { $0.isSource == inputs })
        }
    }
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    title("INPUTS / OUTPUTS")
                    Spacer()
                    Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Refresh the MIDI port list")
                }
                VStack(alignment: .leading, spacing: 6) {
                    portHeading("Inputs", inputs: true)
                    ForEach(model.endpoints.filter(\.isSource)) { endpoint in
                        Toggle(isOn: Binding(get: { model.selectedSources.contains(endpoint.id) }, set: { _ in model.toggleSource(endpoint.id) })) {
                            Text(endpoint.name).lineLimit(2).help(endpoint.name)
                        }.toggleStyle(.checkbox)
                    }
                    if !model.endpoints.contains(where: \.isSource) { Text("No inputs detected").foregroundStyle(.secondary) }
                }
                Divider().overlay(CLR.line)
                VStack(alignment: .leading, spacing: 6) {
                    portHeading("Outputs", inputs: false)
                    Text(model.outputDisplayStatus).font(.caption).foregroundStyle(.secondary)
                    ForEach(model.endpoints.filter { !$0.isSource }) { endpoint in
                        Toggle(isOn: Binding(get: { model.selectedOutputs.contains(endpoint.id) }, set: { _ in model.toggleOutput(endpoint.id) })) {
                            Text(endpoint.name).lineLimit(2).help(endpoint.name)
                        }.toggleStyle(.checkbox)
                    }
                    if !model.endpoints.contains(where: { !$0.isSource }) { Text("No outputs detected").foregroundStyle(.secondary) }
                }
                Divider().overlay(CLR.line)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Receive from software", isOn: Binding(get: { model.virtualEnabled }, set: { _ in model.toggleVirtual() }))
                        .toggleStyle(.checkbox).help("Creates CLR MIDI Monitor — Receive while monitoring is on.")
                    Text("To check your app’s MIDI output, enable this option and Monitoring, then choose CLR MIDI Monitor — Receive as the MIDI output in your app.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !model.driverInstalled {
                        Button(model.installingDriver ? "Installing…" : "Install Output Monitor") {
                            model.installOutputDriver()
                        }.disabled(model.installingDriver)
                        Text("Included with this app. Install once to see MIDI sent by other apps. Close MIDI apps before installing.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if model.outputStatus == "Driver not loaded" {
                        Text("Reopen your MIDI apps when convenient. If it remains unavailable, restart your Mac.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = model.driverInstallError {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(CLR.line)
                title("DISPLAY")
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 6) {
                        Text("Controller Format").font(.caption).foregroundStyle(.secondary)
                        Picker("Controller Format", selection: $model.controllerFormat) {
                            ForEach(ValueFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 180, height: 26)
                    }.frame(width: 180)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 6) {
                            Text("Note Format").font(.caption).foregroundStyle(.secondary)
                            Picker("Note Format", selection: $model.noteFormat) {
                                ForEach(ValueFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 180, height: 26)
                        }.frame(width: 180)
                        VStack(spacing: 6) {
                            Text("Middle C").font(.caption).foregroundStyle(.secondary)
                            Picker("Middle C", selection: $model.middleC) {
                                ForEach(MiddleC.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 72, height: 26)
                                .disabled(model.noteFormat == .decimal)
                        }.frame(width: 72)
                    }
                }.frame(width: 264, alignment: .leading)
                Divider().overlay(CLR.line)
                Toggle("Display filters", isOn: $model.displayFiltersEnabled).toggleStyle(.switch)
                    .help("Apply the filters below to both the latest event and history.")
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Hide Voice Messages", isOn: $model.hideVoiceMessages).toggleStyle(.checkbox)
                        .help("Notes, poly aftertouch, control changes, programs, channel pressure and pitch bend.")
                    Toggle("Hide System Common", isOn: $model.hideSystemCommon).toggleStyle(.checkbox)
                        .help("Time code, song position, song select and tune request.")
                    Toggle("Hide SysEx", isOn: $model.hideSysEx).toggleStyle(.checkbox)
                        .help("System Exclusive messages, including SysEx fragments.")
                    Toggle("Hide Clock", isOn: $model.hideClock).toggleStyle(.checkbox)
                    Toggle("Hide Active Sensing", isOn: $model.hideActiveSensing).toggleStyle(.checkbox)
                    TextField("Search MIDI events", text: $model.search).textFieldStyle(.roundedBorder)
                }.disabled(!model.displayFiltersEnabled)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(CLR.sidebar)
    }
    private var stream: some View {
        GeometryReader { geo in
            let width = max(780, geo.size.width - 32)
            let visible = model.visibleEvents
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    title(model.displayFiltersEnabled && model.hasActiveDisplayFilters ? "LAST OBSERVED EVENT · FILTERED" : "LAST OBSERVED EVENT")
                    Spacer()
                    Button("Clear") { model.clear() }
                }.padding(.bottom, 10)
                columns(width: width)
                eventRow(visible.last, width: width, highlighted: true)
                    .padding(.bottom, 6)
                Divider().overlay(CLR.line)
                title("HISTORY").padding(.vertical, 10)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { event in
                            eventRow(event, width: width)
                                .background(model.selection == event.id ? CLR.amber.opacity(0.13) : Color.clear)
                                .contentShape(Rectangle()).onTapGesture { model.selection = event.id }
                                .contextMenu {
                                    Button("Copy event") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("\(model.time(event))\t\(event.endpointName)\t\(event.kind)\t\(model.formatted(event).summary)\t\(event.hex)", forType: .string)
                                    }
                                }
                            Divider().opacity(0.3)
                        }
                    }
                }.overlay {
                    if !model.running {
                        ZStack {
                            Color.red.opacity(0.16)
                            Text("OFF")
                                .font(.system(size: 40, weight: .semibold))
                                .tracking(4)
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                        .allowsHitTesting(false)
                        .accessibilityLabel("Monitoring off")
                    } else if visible.isEmpty {
                        Text(model.events.isEmpty ? "Waiting for MIDI" : "No matching events")
                            .foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                inspector.padding(.top, 10)
                Divider().overlay(CLR.line).padding(.top, 10)
                HStack {
                    Text("\(model.events.count) captured · \(visible.count) shown")
                    Spacer()
                    Text("\(model.discarded) dropped · \(model.evicted) aged out")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(16)
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                title("INSPECT")
                if let event = model.selectedEvent {
                    Text(event.kind).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Copy raw") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(event.hex, forType: .string)
                    }
                } else {
                    Text("Select an event from the history").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let event = model.selectedEvent {
                HStack(alignment: .top, spacing: 24) {
                    inspectionField("Port", event.endpointName)
                    inspectionField("Group / Channel", "\(event.group) / \(event.channel.map(String.init) ?? "—")")
                    inspectionField("Data", model.formatted(event).summary)
                    inspectionField("MIDI timestamp", String(event.timestamp))
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("Raw UMP").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) { Text(event.hex).font(CLR.rowFont).textSelection(.enabled) }
                }.frame(height: 22)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(CLR.sidebar, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CLR.line))
    }
    private func inspectionField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(CLR.rowFont).lineLimit(2).help(value).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func widths(_ width: CGFloat) -> [CGFloat] {
        let flexible = width - 576
        return [112, 76, flexible, 144, 40, 140, 64]
    }
    private func columns(width: CGFloat) -> some View {
        let names = ["Time", "Path", "Port", "Message", "Ch", "Note / Controller", "Value"]
        let sizes = widths(width)
        return HStack(spacing: 0) {
            ForEach(0..<names.count, id: \.self) { i in
                Text(names[i]).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).frame(width: sizes[i], height: 28, alignment: .leading)
                    .overlay(alignment: .trailing) { Rectangle().fill(CLR.line).frame(width: 1, height: 14) }
            }
        }
    }
    private func eventRow(_ event: MIDIEvent?, width: CGFloat, highlighted: Bool = false) -> some View {
        let display = event.map { model.formatted($0) }
        let values = [event.map { model.time($0) } ?? "—", event?.path.rawValue ?? "—", event?.endpointName ?? "—", event?.kind ?? "—", event?.channel.map(String.init) ?? "—", display?.parameter ?? "—", display?.value ?? "—"]
        let sizes = widths(width)
        return HStack(spacing: 0) {
            ForEach(0..<values.count, id: \.self) { i in
                Text(values[i]).font(CLR.rowFont).lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 6).frame(width: sizes[i], height: 28, alignment: .leading)
                    .background {
                        if highlighted {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(CLR.amber.opacity(0.08))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(CLR.amber.opacity(0.32), lineWidth: 1)
                                }
                                .padding(.horizontal, 2)
                        }
                    }
                    .help(values[i])
            }
        }.accessibilityElement(children: .combine)
    }
}
