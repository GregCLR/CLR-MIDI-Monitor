import AppKit
import Combine
import MIDICore
import MIDICapture
import Darwin

final class MonitorModel: ObservableObject {
    @Published var endpoints: [Endpoint] = []
    @Published var selectedSources: Set<UInt32> = []
    @Published var events: [MIDIEvent] = []
    @Published var running = false
    @Published var virtualEnabled = false
    @Published var error: String?
    @Published var discarded = 0
    @Published var evicted = 0
    @Published var search = ""
    @Published var hideVoiceMessages = false
    @Published var hideSystemCommon = false
    @Published var hideSysEx = false
    var hasActiveDisplayFilters: Bool {
        hideVoiceMessages || hideSystemCommon || hideSysEx || hideClock || hideActiveSensing || !search.isEmpty
    }
    @Published var hideClock = false
    @Published var hideActiveSensing = false
    @Published var noteFormat = ValueFormat(rawValue: UserDefaults.standard.string(forKey: "noteFormat") ?? "") ?? .name { didSet { UserDefaults.standard.set(noteFormat.rawValue, forKey: "noteFormat") } }
    @Published var controllerFormat = ValueFormat(rawValue: UserDefaults.standard.string(forKey: "controllerFormat") ?? "") ?? .name { didSet { UserDefaults.standard.set(controllerFormat.rawValue, forKey: "controllerFormat") } }
    @Published var middleC = MiddleC(rawValue: UserDefaults.standard.string(forKey: "middleC") ?? "") ?? .c3 { didSet { UserDefaults.standard.set(middleC.rawValue, forKey: "middleC") } }
    @Published var displayFiltersEnabled = true
    private let startTicks = mach_absolute_time()
    private let startDate = Date()
    private let clockFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    @Published var selection: UUID?
    private let driverInstaller = OutputDriverInstaller()
    @Published var driverInstalled = false
    @Published var installingDriver = false
    @Published var driverInstallError: String?
    var outputDisplayStatus: String {
        if outputStatus == "Driver not loaded" {
            return driverInstalled ? "Installed · waiting for CoreMIDI" : "Output monitor not installed"
        }
        return outputStatus
    }
    func installOutputDriver() {
        guard !installingDriver else { return }
        installingDriver = true; driverInstallError = nil
        let installer = driverInstaller
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try installer.install() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.installingDriver = false
                self.driverInstalled = installer.isInstalled
                if case .failure(let error) = result { self.driverInstallError = error.localizedDescription }
            }
        }
    }
    private let spy = OutputSpy()
    @Published var outputStatus = "Checking driver…"
    @Published var selectedOutputs: Set<UInt32> = []
    private var outputSelection = SourceSelection()
    private var spyConfiguration: String = ""
    private let engine = MIDIEngine()
    private var timer: AnyCancellable?
    private var discoveryTimer: AnyCancellable?
    private var sourceSelection = SourceSelection()
    private var knownNames: [UInt32: String] = [:]
    private let limit = 10_000
    private var lastClearTicks: UInt64 = 0

    init() {
        spy.onStatus = { [weak self] in self?.outputStatus = $0 }
        spy.startPolling()
        engine.onChange = { [weak self] in self?.refresh() }
        engine.onError = { [weak self] in self?.error = $0 }
        do { try engine.start(); refresh() }
        catch { self.error = error.localizedDescription }
        discoveryTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.drain() }
    }
    var visibleEvents: [MIDIEvent] {
        guard displayFiltersEnabled else { return events }
        return events.filter { event in
            !(hideVoiceMessages && event.category == .voice) &&
            !(hideSystemCommon && event.category == .systemCommon) &&
            !(hideSysEx && event.category == .systemExclusive) &&
            !(hideClock && event.kind == "Clock") && !(hideActiveSensing && event.kind == "Active Sensing") &&
            (search.isEmpty || "\(event.endpointName) \(event.kind) \(formatted(event).summary) \(event.detail) \(event.hex)".localizedCaseInsensitiveContains(search))
        }
    }
    var latestEvent: MIDIEvent? { visibleEvents.last }
    func formatted(_ event: MIDIEvent) -> EventDisplay {
        MIDIFormat.display(event, notes: noteFormat, controllers: controllerFormat, middleC: middleC)
    }
    func time(_ event: MIDIEvent) -> String {
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        let seconds = (Double(event.receivedAt) - Double(startTicks)) * Double(info.numer) / Double(info.denom) / 1_000_000_000
        return clockFormatter.string(from: startDate.addingTimeInterval(seconds))
    }
    var selectedEvent: MIDIEvent? { events.first { $0.id == selection } }
    func refresh() {
        let installed = driverInstaller.isInstalled
        if installed != driverInstalled { driverInstalled = installed }
        let discovered = engine.endpoints()
        if endpoints != discovered { endpoints = discovered }
        for endpoint in endpoints { knownNames[endpoint.id] = endpoint.name }
        let enabled = Set(endpoints.filter { $0.isSource && sourceSelection.isEnabled($0.uniqueID) }.map(\.id))
        if selectedSources != enabled { selectedSources = enabled }
        selectedOutputs = Set(endpoints.filter { !$0.isSource && outputSelection.isEnabled($0.uniqueID) }.map(\.id))
        updateSpy()
        if running { engine.connect(selectedSources) }
    }
    private func updateSpy() {
        let configuration = "\(running):\(selectedOutputs.sorted())"
        guard configuration != spyConfiguration else { return }
        spyConfiguration = configuration
        spy.configure(enabled: running, destinations: selectedOutputs)
    }
    func allPortsSelected(inputs: Bool) -> Bool {
        let ports = endpoints.filter { $0.isSource == inputs }
        let selection = inputs ? selectedSources : selectedOutputs
        return !ports.isEmpty && ports.allSatisfy { selection.contains($0.id) }
    }
    func setAllPorts(_ enabled: Bool, inputs: Bool) {
        let ids = endpoints.filter { $0.isSource == inputs }.map(\.uniqueID)
        if inputs { sourceSelection.setEnabled(enabled, for: ids) }
        else { outputSelection.setEnabled(enabled, for: ids) }
        refresh()
    }
    func toggleOutput(_ id: UInt32) {
        guard let endpoint = endpoints.first(where: { $0.id == id && !$0.isSource }) else { return }
        outputSelection.setEnabled(!selectedOutputs.contains(id), for: endpoint.uniqueID)
        refresh()
    }
    func toggleSource(_ id: UInt32) {
        guard let endpoint = endpoints.first(where: { $0.id == id && $0.isSource }) else { return }
        sourceSelection.setEnabled(!selectedSources.contains(id), for: endpoint.uniqueID)
        refresh()
    }
    func toggleCapture() {
        defer { updateSpy() }
        guard engine.isReady else { error = "CoreMIDI is unavailable. Restart the app after resolving the startup error."; return }
        if running {
            engine.connect([])
            do { try engine.setVirtual(false) } catch { self.error = error.localizedDescription }
            running = false
            drain() // Preserve already queued events when stopping.
        } else {
            engine.connect(selectedSources)
            do { try engine.setVirtual(virtualEnabled); running = true }
            catch { engine.connect([]); self.error = error.localizedDescription }
        }
    }
    func toggleVirtual() {
        let next = !virtualEnabled
        do { if running { try engine.setVirtual(next) }; virtualEnabled = next }
        catch { self.error = error.localizedDescription }
    }
    func clear() {
        lastClearTicks = mach_absolute_time()
        _ = engine.inbox.drain()
        _ = spy.drain()
        events.removeAll(); selection = nil; discarded = 0; evicted = 0
    }
    private func drain() {
        let batch = engine.inbox.drain()
        let output = spy.drain()
        discarded += batch.dropped + output.dropped
        let packets = batch.packets + (running ? output.packets.filter { selectedOutputs.contains($0.endpoint) } : [])
        let decoded = packets.filter { $0.receivedAt >= lastClearTicks }.sorted { $0.receivedAt < $1.receivedAt }.flatMap {
            UMPDecoder.decode($0, name: $0.path == .virtual ? "CLR Receive" : knownNames[$0.endpoint] ?? "Port \($0.endpoint)")
        }
        append(decoded)
    }
    private func append(_ decoded: [MIDIEvent]) {
        guard !decoded.isEmpty else { return }
        if let last = events.last, let first = decoded.first, first.receivedAt < last.receivedAt {
            events = (events + decoded).sorted { $0.receivedAt < $1.receivedAt }
        } else { events.append(contentsOf: decoded) }
        if events.count > limit {
            let count = events.count - limit; events.removeFirst(count); evicted += count
        }
    }
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CLR MIDI Capture.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(events).write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
}
