import XCTest
@testable import OSCCore

func oscString(_ value: String) -> Data {
    var data = Data(value.utf8); data.append(0)
    while data.count % 4 != 0 { data.append(0) }; return data
}
func word(_ value: UInt32) -> Data { Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
func bundle(_ items: [Data], tag: UInt32 = 1) -> Data {
    var data = oscString("#bundle") + word(0) + word(tag)
    for item in items { data += word(UInt32(item.count)); data += item }; return data
}
final class OSCDecoderTests: XCTestCase {
    func testBasicTypesAndBigEndian() throws {
        let data = oscString("/fader/1") + oscString(",ifsb") + word(UInt32.max) + word(Float(0.5).bitPattern) + oscString("hello") + word(3) + Data([1,2,3,0])
        let result = try OSCDecoder.decode(data)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].address, "/fader/1")
        XCTAssertEqual(result[0].arguments, ["-1", "0.5", "\"hello\"", "blob[3] 010203"])
    }
    func testZeroPayloadAndArrayTypes() throws {
        let result = try OSCDecoder.decode(oscString("/flags") + oscString(",[TFNI]"))
        XCTAssertEqual(result[0].arguments, ["[", "true", "false", "nil", "infinitum", "]"])
    }
    func testNestedBundleOrderAndTimetags() throws {
        let message = oscString("/go") + oscString(",i") + word(7)
        let result = try OSCDecoder.decode(bundle([message, bundle([message], tag: 2)]))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].timeTags, ["0000000000000001"])
        XCTAssertEqual(result[1].timeTags, ["0000000000000001", "0000000000000002"])
    }
    func testEmptyBundleVisible() throws { XCTAssertTrue(try OSCDecoder.decode(bundle([]))[0].isBundle) }
    func testRejectsTruncationPaddingUnknownTagsAndTrailingBytes() {
        let good = oscString("/x") + oscString(",i") + word(9)
        for length in 0..<good.count { XCTAssertThrowsError(try OSCDecoder.decode(good.prefix(length))) }
        XCTAssertThrowsError(try OSCDecoder.decode(oscString("/x") + oscString(",q")))
        XCTAssertThrowsError(try OSCDecoder.decode(good + word(0)))
        XCTAssertThrowsError(try OSCDecoder.decode(oscString("/x") + oscString(",]")))
        XCTAssertThrowsError(try OSCDecoder.decode(Data([47,120,0,99]) + oscString(",")))
        XCTAssertThrowsError(try OSCDecoder.decode(oscString("/x") + oscString(",b") + word(UInt32.max)))
    }
    func testBundleAndArgumentLimits() {
        var nested = oscString("/x") + oscString(",")
        for _ in 0..<18 { nested = bundle([nested]) }
        XCTAssertThrowsError(try OSCDecoder.decode(nested))
        XCTAssertThrowsError(try OSCDecoder.decode(bundle(Array(repeating: oscString("/x") + oscString(","), count: 257))))
        XCTAssertThrowsError(try OSCDecoder.decode(oscString("/x") + oscString("," + String(repeating: "T", count: 257))))
    }
    func testMalformedPacketCorpusDoesNotCrash() {
        var state: UInt64 = 42
        for length in stride(from: 4, through: 2048, by: 4) {
            let bytes: [UInt8] = (0..<length).map { _ in state = state &* 6364136223846793005 &+ 1; return UInt8(truncatingIfNeeded: state >> 32) }
            _ = try? OSCDecoder.decode(Data(bytes))
        }
    }
}
