import XCTest
@testable import MIDICore

final class FormatTests: XCTestCase {
    func event(_ word: UInt32) -> MIDIEvent {
        UMPDecoder.decode(CapturedPacket(endpoint: 1, path: .input, timestamp: 0, receivedAt: 1, words: [word]), name: "Test")[0]
    }
    func testNoteConventionAndDecimalPreserveRaw() {
        let e = event(0x20903C64)
        XCTAssertEqual(MIDIFormat.display(e, notes: .name, controllers: .name, middleC: .c3).parameter, "C3")
        XCTAssertEqual(MIDIFormat.display(e, notes: .name, controllers: .name, middleC: .c4).parameter, "C4")
        XCTAssertEqual(MIDIFormat.display(e, notes: .decimal, controllers: .name, middleC: .c4).parameter, "60")
        XCTAssertEqual(e.hex, "20903C64")
        XCTAssertEqual(MIDIFormat.note(0, format: .name, middleC: .c3), "C-2")
        XCTAssertEqual(MIDIFormat.note(127, format: .name, middleC: .c4), "G9")
    }
    func testControllerNameDecimalAndUndefinedFallback() {
        let e = event(0x20B04A60)
        XCTAssertEqual(MIDIFormat.display(e, notes: .name, controllers: .name, middleC: .c3).parameter, "Brightness")
        XCTAssertEqual(MIDIFormat.display(e, notes: .name, controllers: .decimal, middleC: .c3).parameter, "74")
        XCTAssertEqual(MIDIFormat.controller(119, format: .name), "119")
        XCTAssertEqual(MIDIFormat.display(e, notes: .name, controllers: .name, middleC: .c3).value, "96")
    }
    func testZeroVelocityAndSystemFields() {
        let off = event(0x20903C00)
        XCTAssertEqual(off.kind, "Note Off")
        XCTAssertEqual(MIDIFormat.display(off, notes: .name, controllers: .name, middleC: .c3).value, "0")
        let clock = MIDIFormat.display(event(0x10F80000), notes: .name, controllers: .name, middleC: .c3)
        XCTAssertEqual(clock.parameter, "—")
        XCTAssertEqual(clock.value, "—")
    }
}
