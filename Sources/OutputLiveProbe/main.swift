import Foundation
import CoreMIDI
import MIDICore
import MIDICapture

// Explicit controlled live validation. No hardware or pre-existing destination
// is ever selected: sends target only the destination created by this process.
func check(_ status: OSStatus) throws {
    if status != noErr { throw NSError(domain: "OutputLiveProbe", code: Int(status)) }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "OutputLiveProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
do {
    let spy = OutputSpy(), received = PacketInbox()
    var status = "", client: MIDIClientRef = 0, port: MIDIPortRef = 0, destination: MIDIEndpointRef = 0
    spy.onStatus = { status = $0 }
    try check(MIDIClientCreate("CLR isolated output validation" as CFString,nil,nil,&client))
    defer { MIDIClientDispose(client) }
    try check(MIDIOutputPortCreate(client,"Owned test sender" as CFString,&port))
    try check(MIDIDestinationCreateWithProtocol(client,"CLR temporary output validation" as CFString,._1_0,&destination) { list, _ in
        received.capture(list,endpoint:0,path:.virtual)
    })
    spy.configure(enabled:true,destinations:[destination]); spy.startPolling()
    RunLoop.current.run(until:Date().addingTimeInterval(0.6))
    try require(status == "Output monitoring active", "No sends performed: \(status)")
    let list=UnsafeMutablePointer<MIDIEventList>.allocate(capacity:1)
    defer { list.deallocate() }
    let packet=MIDIEventListInit(list,._1_0)
    let words:[UInt32]=[0x20903C64,0x20B04A60,0x20803C40,0x10F80000,0x10FE0000]
    words.withUnsafeBufferPointer { buffer in
        _ = MIDIEventListAdd(list,MemoryLayout<MIDIEventList>.size,packet,0,words.count,buffer.baseAddress!)
    }
    try check(MIDISendEventList(port,destination,list))
    RunLoop.current.run(until:Date().addingTimeInterval(0.6))
    let receiver=received.drain(), observed=spy.drain()
    try require(receiver.packets.flatMap(\.words)==words && receiver.dropped==0,"Receiver data changed or duplicated")
    try require(observed.packets.flatMap(\.words)==words && observed.dropped==0,"Observed output data missing, changed or duplicated")
    try require(observed.packets.allSatisfy { $0.endpoint==destination && $0.path == .outputSpy },"Incorrect output attribution")
    RunLoop.current.run(until:Date().addingTimeInterval(0.3))
    try require(received.drain().packets.isEmpty && spy.drain().packets.isEmpty,"Unexpected traffic after finite send; possible duplication")
    spy.configure(enabled:false,destinations:[])
    RunLoop.current.run(until:Date().addingTimeInterval(0.2))
    try check(MIDISendEventList(port,destination,list))
    RunLoop.current.run(until:Date().addingTimeInterval(0.4))
    try require(received.drain().packets.flatMap(\.words)==words,"Delivery affected by Monitoring Off")
    try require(spy.drain().packets.isEmpty,"Output capture remained active after Off")
    print("PASS: owned destination received exactly five messages with monitoring on and five with it off; exact OUT copies only while on; no spontaneous extra traffic. No external destinations targeted.")
} catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
