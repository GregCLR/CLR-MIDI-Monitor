import AppKit
import Combine
import OSCCore

struct OSCEvent: Identifiable, Codable {
    let id: UUID
    let receivedAt: Date
    let sender: String
    let senderPort: UInt16
    let localPort: UInt16
    let message: OSCMessage?
    let error: String?
    let packet: Data
    var address: String { message?.address ?? "Invalid OSC" }
    var arguments: String { error ?? message?.arguments.joined(separator: " · ") ?? "" }
    var source: String { "\(sender):\(senderPort)" }
    var hex: String { packet.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

final class OSCModel: ObservableObject {
    @Published var port = "9001"
    @Published var network = false
    @Published private(set) var running = false
    @Published private(set) var events: [OSCEvent] = []
    @Published var error: String?
    @Published var search = ""
    @Published var senderFilter = ""
    @Published var filtersEnabled = true
    @Published var hideInvalid = false
    @Published var selection: UUID?
    @Published private(set) var dropped = 0
    @Published private(set) var evicted = 0
    @Published private(set) var invalid = 0
    private var historyBytes = 0
    private let receiver = OSCReceiver()
    private var timer: AnyCancellable?
    private let formatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    init() {
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.drain() }
    }
    deinit { receiver.stop() }
    var visibleEvents: [OSCEvent] {
        guard filtersEnabled else { return events }
        return events.filter {
            (!hideInvalid || $0.error == nil) &&
            (senderFilter.isEmpty || $0.source.localizedCaseInsensitiveContains(senderFilter)) &&
            (search.isEmpty || "\($0.address) \($0.message?.types ?? "") \($0.arguments)".localizedCaseInsensitiveContains(search))
        }
    }
    func time(_ event: OSCEvent) -> String { formatter.string(from: event.receivedAt) }
    func toggle() {
        if running { receiver.stop(); running = false; return }
        guard let portNumber = UInt16(port), portNumber >= 1024 else {
            error = "Choose an unused UDP port from 1024 to 65535."; return
        }
        do {
            _ = try receiver.start(port: portNumber, network: network)
            error = nil; running = true; dropped = 0
        } catch { self.error = error.localizedDescription; running = false }
    }
    func clear() {
        receiver.clear(); events.removeAll(); historyBytes = 0
        dropped = 0; evicted = 0; invalid = 0; selection = nil
    }
    private func drain() {
        guard running else { return }
        let batch = receiver.drain()
        dropped = batch.dropped
        if let error = batch.error { self.error = error; receiver.stop(); running = false }
        var additions: [OSCEvent] = []
        for packet in batch.packets {
            do {
                for message in try OSCDecoder.decode(packet.data) {
                    additions.append(OSCEvent(id: UUID(), receivedAt: packet.receivedAt, sender: packet.sender, senderPort: packet.senderPort, localPort: packet.localPort, message: message, error: nil, packet: packet.data))
                }
            } catch {
                invalid += 1
                additions.append(OSCEvent(id: UUID(), receivedAt: packet.receivedAt, sender: packet.sender, senderPort: packet.senderPort, localPort: packet.localPort, message: nil, error: error.localizedDescription, packet: packet.data))
            }
        }
        guard !additions.isEmpty else { return }
        // Charge every row for its original packet and decoded text, even when
        // Data storage is shared. Both row count and retained content are bounded.
        func cost(_ event: OSCEvent) -> Int { event.packet.count + event.arguments.utf8.count + event.address.utf8.count + 512 }
        var updated = events + additions
        historyBytes += additions.reduce(0) { $0 + cost($1) }
        var remove = 0
        while updated.count - remove > 10_000 || historyBytes > 16_777_216 {
            historyBytes -= cost(updated[remove]); remove += 1
        }
        if remove > 0 { updated.removeFirst(remove); evicted += remove }
        events = updated
        if let selection, !events.contains(where: { $0.id == selection }) { self.selection = nil }
    }
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CLR OSC Capture.json"
        panel.allowedFileTypes = ["json"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(events).write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
}
