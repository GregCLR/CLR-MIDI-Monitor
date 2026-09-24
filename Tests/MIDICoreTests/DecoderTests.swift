import XCTest
@testable import MIDICore

final class DecoderTests: XCTestCase {
    func decode(_ words: [UInt32]) -> [MIDIEvent] {
        UMPDecoder.decode(CapturedPacket(endpoint: 4, path: .input, timestamp: 0, receivedAt: 99, words: words), name: "Test")
    }
    func testZeroVelocityNoteRetainsRawAndTimestamp() {
        let event = decode([0x20903C00])[0]
        XCTAssertEqual(event.kind, "Note Off")
        XCTAssertEqual(event.hex, "20903C00")
        XCTAssertEqual(event.timestamp, 0)
        XCTAssertEqual(event.receivedAt, 99)
        XCTAssertEqual(event.channel, 1)
    }
    func testMultiwordMessagesDoNotDesynchronizeClock() {
        let events = decode([0x40903C00, 0xFFFFFFFF, 0x10F80000])
        XCTAssertEqual(events.map(\.kind), ["MIDI 2.0", "Clock"])
        XCTAssertNil(events[1].channel)
    }
    func testTruncatedPacketIsVisible() {
        XCTAssertEqual(decode([0x40903C00])[0].kind, "Malformed")
    }
    func testSustainAndPitchBend() {
        let events = decode([0x23B2407F, 0x20E00040])
        XCTAssertEqual(events[0].group, 4)
        XCTAssertEqual(events[0].channel, 3)
        XCTAssertTrue(events[0].detail.contains("sustain on"))
        XCTAssertEqual(events[1].detail, "0")
    }
    func testBoundedInboxReportsLossAndDrains() {
        let inbox = PacketInbox(capacity: 1)
        let packet = CapturedPacket(endpoint: 1, path: .input, timestamp: 0, receivedAt: 1, words: [0x10F80000])
        inbox.append(packet); inbox.append(packet)
        let batch = inbox.drain()
        XCTAssertEqual(batch.packets.count, 1); XCTAssertEqual(batch.dropped, 1)
        XCTAssertEqual(inbox.drain().packets.count, 0)
        XCTAssertEqual(inbox.drain().dropped, 0)
    }
}
