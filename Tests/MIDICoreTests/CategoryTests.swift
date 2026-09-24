import XCTest
@testable import MIDICore

final class CategoryTests: XCTestCase {
    func category(_ words: [UInt32]) -> MIDIEvent.Category {
        UMPDecoder.decode(CapturedPacket(endpoint: 1, path: .input, timestamp: 0, receivedAt: 0, words: words), name: "Test")[0].category
    }
    func testVoiceFamilies() {
        for status: UInt32 in [0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0] {
            XCTAssertEqual(category([0x20000000 | status << 16]), .voice)
        }
        XCTAssertEqual(category([0x40903C00, 0]), .voice)
    }
    func testCommonDoesNotIncludeRealtime() {
        for status: UInt32 in [0xF1, 0xF2, 0xF3, 0xF6] {
            XCTAssertEqual(category([0x10000000 | status << 16]), .systemCommon)
        }
        for status: UInt32 in [0xF8, 0xFA, 0xFB, 0xFC, 0xFE, 0xFF] {
            XCTAssertEqual(category([0x10000000 | status << 16]), .realTime)
        }
    }
    func testSysExDoesNotHideOtherDataOrMalformedPackets() {
        XCTAssertEqual(category([0x30000000, 0]), .systemExclusive)
        XCTAssertEqual(category([0x50300000, 0, 0, 0]), .systemExclusive)
        XCTAssertEqual(category([0x50800000, 0, 0, 0]), .other)
        XCTAssertEqual(category([0x30000000]), .other)
    }
}
