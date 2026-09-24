import Foundation

/// Validated IPC data; never reads struct padding or assumes buffer alignment.
public struct OutputSpyBatch {
    public let status: UInt32
    public let dropped: UInt64
    public let packets: [CapturedPacket]
    public static func decode(_ data: Data) throws -> OutputSpyBatch {
        enum Invalid: Error { case response }
        var offset = 0
        func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            guard offset + MemoryLayout<T>.size <= data.count else { throw Invalid.response }
            var value: T = 0
            _ = withUnsafeMutableBytes(of: &value) { destination in
                data.copyBytes(to: destination, from: offset..<(offset + MemoryLayout<T>.size))
            }
            offset += MemoryLayout<T>.size
            return T(littleEndian: value)
        }
        guard try read(UInt32.self) == 0x43535031 else { throw Invalid.response }
        let status = try read(UInt32.self), dropped = try read(UInt64.self), count = try read(UInt32.self)
        guard status <= 4, count <= 64, (status == 0 || count == 0) else { throw Invalid.response }
        var packets: [CapturedPacket] = []
        for _ in 0..<count {
            let endpoint = try read(UInt32.self), timestamp = try read(UInt64.self), arrival = try read(UInt64.self)
            let length = try read(UInt32.self)
            guard length <= 4096, Int(length) * 4 <= data.count - offset else { throw Invalid.response }
            var words: [UInt32] = []; words.reserveCapacity(Int(length))
            for _ in 0..<length { words.append(try read(UInt32.self)) }
            packets.append(CapturedPacket(endpoint: endpoint, path: .outputSpy, timestamp: timestamp, receivedAt: arrival, words: words))
        }
        guard offset == data.count else { throw Invalid.response }
        return OutputSpyBatch(status: status, dropped: dropped, packets: packets)
    }
    public static func request(token: UInt64, destinations: Set<UInt32>) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(token); append(UInt32(destinations.count))
        for endpoint in destinations.sorted() { append(endpoint) }
        return data
    }
}
