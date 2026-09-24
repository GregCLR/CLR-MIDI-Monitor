import CoreFoundation
import Foundation
import MIDICore
import Darwin

/// All IPC happens on this private serial queue, never the MIDI or UI threads.
public final class OutputSpy {
    private let worker = DispatchQueue(label: "com.clr.midimonitor.output-reader", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var remote: CFMessagePort?
    private var destinations: Set<UInt32> = []
    private var enabled = false
    private let inbox = PacketInbox()
    private let dropLock = NSLock()
    private var driverDrops: UInt64 = 0
    private let token = UInt64.random(in: 1...UInt64.max)
    public var onStatus: ((String) -> Void)?
    private var lastStatus = ""
    private let portName: String
    public init(portName: String? = nil) {
        self.portName = portName ?? "com.clr.midimonitor.spy.v1.\(getuid())"
    }
    public func startPolling() {
        worker.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.worker)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer; timer.resume()
        }
    }
    // Called on main; worker serializes configuration and IPC.
    public func configure(enabled: Bool, destinations: Set<UInt32>) {
        worker.async { [weak self] in
            guard let self else { return }
            if self.enabled && !enabled {
                if let remote = self.remote, self.ownsLease { self.sendStop(remote); self.ownsLease = false }
                _ = self.inbox.drain()
            }
            self.enabled = enabled; self.destinations = destinations
        }
    }
    private var nextProbe = Date.distantPast
    private var ownsLease = false
    private func status(_ message: String) {
        guard message != lastStatus else { return }
        lastStatus = message
        DispatchQueue.main.async { [weak self] in self?.onStatus?(message) }
    }
    private func poll() {
        if let remote, !CFMessagePortIsValid(remote) { self.remote = nil; ownsLease = false }
        if remote == nil {
            guard Date() >= nextProbe else { return }
            nextProbe = Date().addingTimeInterval(2)
            remote = CFMessagePortCreateRemote(nil, portName as CFString)
        }
        guard let remote else { status("Driver not loaded"); return }
        guard enabled && !destinations.isEmpty else {
            if ownsLease { sendStop(remote); ownsLease = false }
            status("Driver available · idle"); return
        }
        guard destinations.count <= 256 else { status("Select up to 256 outputs"); return }
        let data = OutputSpyBatch.request(token: token, destinations: destinations)
        var reply: Unmanaged<CFData>?
        let result = CFMessagePortSendRequest(remote, 1, data as CFData, 0.02, 0.1, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard result == kCFMessagePortSuccess, let reply else {
            self.remote = nil; ownsLease = false; status("Driver connection unavailable"); return
        }
        do {
            let batch = try OutputSpyBatch.decode(reply.takeRetainedValue() as Data)
            guard batch.status == 0 else {
                ownsLease = false
                status(batch.status == 2 ? "Driver in use by another monitor" : "Driver monitoring unavailable")
                return
            }
            ownsLease = true; status("Output monitoring active")
            for packet in batch.packets where destinations.contains(packet.endpoint) { inbox.append(packet) }
            dropLock.lock(); driverDrops &+= batch.dropped; dropLock.unlock()
        } catch { status("Driver response invalid"); self.remote = nil }
    }
    public func drain() -> (packets: [CapturedPacket], dropped: Int) {
        let batch = inbox.drain()
        dropLock.lock(); let dropped = driverDrops; driverDrops = 0; dropLock.unlock()
        return (batch.packets, batch.dropped + Int(clamping: dropped))
    }
    private func sendStop(_ port: CFMessagePort) {
        let data = OutputSpyBatch.request(token: token, destinations: [])
        _ = CFMessagePortSendRequest(port, 2, data as CFData, 0.02, 0, nil, nil)
    }
    deinit {
        timer?.cancel()
        // Do not block shutdown. Driver's short lease expires if no further polls arrive.
    }
}
