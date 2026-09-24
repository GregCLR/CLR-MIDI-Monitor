import Foundation
import CoreMIDI
import MIDICapture
import MIDICore

func check(_ status: OSStatus) throws {
    if status != noErr { throw NSError(domain: "Probe.CoreMIDI", code: Int(status)) }
}
do {
    let engine = MIDIEngine()
    try engine.start()
    try engine.setVirtual(true)
    var client: MIDIClientRef = 0, output: MIDIPortRef = 0, source: MIDIEndpointRef = 0
    try check(MIDIClientCreate("CLR isolated capture test" as CFString, nil, nil, &client))
    defer { MIDIClientDispose(client); engine.stop() }
    try check(MIDIOutputPortCreate(client, "Test sender" as CFString, &output))
    try check(MIDISourceCreateWithProtocol(client, "CLR test source" as CFString, ._1_0, &source))
    engine.connect([source])
    let list = UnsafeMutablePointer<MIDIEventList>.allocate(capacity: 1)
    defer { list.deallocate() }
    let packet = MIDIEventListInit(list, ._1_0)
    let words: [UInt32] = [0x20903C64, 0x20B04A60, 0x20803C00, 0x10F80000, 0x10FE0000]
    words.withUnsafeBufferPointer { ptr in
        _ = MIDIEventListAdd(list, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, ptr.baseAddress!)
    }
    try check(MIDISendEventList(output, engine.receiveEndpoint, list))
    try check(MIDIReceivedEventList(source, list))
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let batch = engine.inbox.drain()
    let events = batch.packets.flatMap { UMPDecoder.decode($0, name: "Isolated test") }
    guard events.filter({ $0.path == .virtual }).count == 5,
          events.filter({ $0.path == .input }).count == 5, batch.dropped == 0 else {
        throw NSError(domain: "Capture verification", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 5 virtual + 5 input events; got \(events.count), drops \(batch.dropped)"])
    }
    print("PASS: 5 source events and 5 virtual-destination events captured through CoreMIDI; zero drops. No external destination was targeted.")
} catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
