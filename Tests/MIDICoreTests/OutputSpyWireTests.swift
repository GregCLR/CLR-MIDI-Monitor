import XCTest
@testable import MIDICore
final class OutputSpyWireTests: XCTestCase {
    func response(status: UInt32 = 0, length: UInt32 = 1) -> Data {
        var data = Data()
        func add<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        add(UInt32(0x43535031)); add(status); add(UInt64(7)); add(UInt32(1))
        add(UInt32(42)); add(UInt64(123)); add(UInt64(456)); add(length); add(UInt32(0x20903C64))
        return data
    }
    func testDestinationRawDataAndTimestampsSurviveIPC() throws {
        let batch = try OutputSpyBatch.decode(response())
        XCTAssertEqual(batch.dropped, 7)
        XCTAssertEqual(batch.packets.count, 1)
        XCTAssertEqual(batch.packets[0].path, .outputSpy)
        XCTAssertEqual(batch.packets[0].endpoint, 42)
        XCTAssertEqual(batch.packets[0].words, [0x20903C64])
        XCTAssertEqual(batch.packets[0].timestamp, 123)
        XCTAssertEqual(batch.packets[0].receivedAt, 456)
    }
    func testEveryTruncationRejected() {
        let data = response()
        for length in 0..<data.count { XCTAssertThrowsError(try OutputSpyBatch.decode(data.prefix(length))) }
    }
    func testCorruptResponseRejected() {
        XCTAssertThrowsError(try OutputSpyBatch.decode(response(length: 4097)))
        XCTAssertThrowsError(try OutputSpyBatch.decode(response(status: 2)))
        var extra = response(); extra.append(0)
        XCTAssertThrowsError(try OutputSpyBatch.decode(extra))
        var magic = response(); magic[0] = 0
        XCTAssertThrowsError(try OutputSpyBatch.decode(magic))
    }
}
