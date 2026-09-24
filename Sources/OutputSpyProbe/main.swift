import Foundation
import Darwin
import MIDICapture
import MIDICore

// Run against Driver/Tests.c --serve. No CoreMIDI client or send API is used.
let spy = OutputSpy(portName: "com.clr.midimonitor.spy.test.v1.\(getuid())")
var status = ""
spy.onStatus = { status = $0 }
spy.configure(enabled: true, destinations: [42])
spy.startPolling()
RunLoop.current.run(until: Date().addingTimeInterval(0.7))
let batch = spy.drain()
precondition(!batch.packets.isEmpty, "No output packets received: \(status)")
precondition(batch.dropped == 0)
precondition(batch.packets.allSatisfy { $0.endpoint == 42 && $0.path == .outputSpy && $0.words == [0x20903C64,0x20B04A60,0x20803C00] && $0.timestamp == 123 })
spy.configure(enabled: true, destinations: [99])
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
_ = spy.drain()
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
precondition(spy.drain().packets.isEmpty, "Deselected endpoint still captured")
spy.configure(enabled: false, destinations: [])
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
precondition(status == "Driver available · idle", status)
print("PASS: Swift output adapter → isolated driver IPC → original packet/timestamps; destination deselection and Monitoring Off verified; no MIDI sends.")
