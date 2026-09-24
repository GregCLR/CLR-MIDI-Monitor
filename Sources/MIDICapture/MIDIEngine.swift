import CoreMIDI
import Foundation
import MIDICore
import Darwin

public struct Endpoint: Identifiable, Equatable {
    public let id: MIDIEndpointRef
    public let uniqueID: Int32
    public let name: String
    public let isSource: Bool
}

/// Owns CoreMIDI references on the main thread. The inbox is the callback boundary.
public final class MIDIEngine {
    public init() {}
    public var receiveEndpoint: MIDIEndpointRef { destination }
    public let inbox = PacketInbox()
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var destination: MIDIEndpointRef = 0
    public var isReady: Bool { client != 0 && input != 0 }
    public private(set) var connected: Set<MIDIEndpointRef> = []
    public var onChange: (() -> Void)?
    public var onError: ((String) -> Void)?

    public func start() throws {
        guard client == 0 else { return }
        do {
            try check(MIDIClientCreateWithBlock("CLR MIDI Monitor" as CFString, &client) { [weak self] _ in
                DispatchQueue.main.async { self?.onChange?() }
            }, "Create MIDI client")
            let inbox = inbox
            try check(MIDIInputPortCreateWithProtocol(client, "CLR Inputs" as CFString, ._1_0, &input) { list, context in
                inbox.capture(list, endpoint: UInt32(UInt(bitPattern: context)), path: .input)
            }, "Create input port")
        } catch { stop(); throw error }
    }

    public func endpoints() -> [Endpoint] {
        let sources = (0..<MIDIGetNumberOfSources()).map { endpoint(MIDIGetSource($0), source: true) }
        let destinations = (0..<MIDIGetNumberOfDestinations()).map { endpoint(MIDIGetDestination($0), source: false) }
        return (sources + destinations).filter { $0.id != 0 && $0.id != destination }
    }

    public func connect(_ desired: Set<MIDIEndpointRef>) {
        guard input != 0 else { return }
        for ref in connected.subtracting(desired) {
            let status = MIDIPortDisconnectSource(input, ref)
            if status != noErr { onError?("Disconnect source: OSStatus \(status)") }
            connected.remove(ref)
        }
        for ref in desired.subtracting(connected) {
            let status = MIDIPortConnectSource(input, ref, UnsafeMutableRawPointer(bitPattern: UInt(ref)))
            if status == noErr { connected.insert(ref) }
            else { onError?("Connect source: OSStatus \(status)") }
        }
    }

    public func setVirtual(_ enabled: Bool) throws {
        guard client != 0 else { return }
        if enabled && destination == 0 {
            let inbox = inbox
            try check(MIDIDestinationCreateWithProtocol(client, "CLR MIDI Monitor — Receive" as CFString, ._1_0, &destination) { list, _ in
                inbox.capture(list, endpoint: 0, path: .virtual)
            }, "Create virtual destination")
        } else if !enabled && destination != 0 {
            try check(MIDIEndpointDispose(destination), "Remove virtual destination"); destination = 0
        }
    }

    public func stop() {
        if client != 0 { MIDIClientDispose(client) }
        client = 0; input = 0; destination = 0; connected.removeAll()
    }
    deinit { stop() }

    private func endpoint(_ ref: MIDIEndpointRef, source: Bool) -> Endpoint {
        var value: Unmanaged<CFString>?, uid: Int32 = 0
        MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &value)
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
        return Endpoint(id: ref, uniqueID: uid, name: value?.takeRetainedValue() as String? ?? "Unnamed port \(ref)", isSource: source)
    }
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw NSError(domain: "CoreMIDI", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(operation): OSStatus \(status)"]) }
    }
}

