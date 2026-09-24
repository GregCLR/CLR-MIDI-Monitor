import CaptureTransport
import CoreMIDI
import Foundation

public struct PacketBatch {
    public let packets: [CapturedPacket]
    public let full: UInt64
    public let contention: UInt64
    public let oversized: UInt64
    public var dropped: Int { Int(full + contention + oversized) }
}

/// Preallocated C transport. Producers never wait; contention is reported as loss.
/// Swift allocations and decoding occur on the consumer, outside MIDI callbacks.
public final class PacketInbox: @unchecked Sendable {
    private let queue: OpaquePointer
    private let capacity: Int
    public init(capacity: Int = 512) {
        self.capacity = min(4096, max(1, capacity))
        guard let queue = CLRQueueCreate(UInt32(self.capacity)) else { preconditionFailure("Cannot allocate MIDI capture queue") }
        self.queue = queue
    }
    deinit { CLRQueueDestroy(queue) }

    public func capture(_ list: UnsafePointer<MIDIEventList>, endpoint: UInt32, path: CapturePath) {
        CLRQueueCapture(queue, list, endpoint, path.transportCode)
    }
    /// For fixtures/tests and future IPC consumers. Live input callbacks use capture().
    public func append(_ packet: CapturedPacket) {
        packet.words.withUnsafeBufferPointer {
            _ = CLRQueuePush(queue, packet.endpoint, packet.path.transportCode,
                             packet.timestamp, packet.receivedAt, $0.baseAddress, UInt32($0.count))
        }
    }
    public func drain() -> PacketBatch {
        var result: [CapturedPacket] = []
        var record = CLRPacketRecord()
        // Bound work even if a producer continuously refills while draining.
        for _ in 0..<capacity {
            guard CLRQueuePop(queue, &record) else { break }
            let count = Int(record.wordCount)
            let words = withUnsafeBytes(of: &record.words) { Array($0.bindMemory(to: UInt32.self).prefix(count)) }
            result.append(CapturedPacket(endpoint: record.endpoint, path: CapturePath(transportCode: record.path),
                timestamp: record.timestamp, receivedAt: record.receivedAt, words: words))
        }
        let drops = CLRQueueTakeDrops(queue)
        return PacketBatch(packets: result, full: drops.full, contention: drops.contention, oversized: drops.oversized)
    }
}

private extension CapturePath {
    var transportCode: UInt8 {
        switch self { case .input: return 0; case .virtual: return 1; case .outputSpy: return 2 }
    }
    init(transportCode: UInt8) {
        switch transportCode { case 1: self = .virtual; case 2: self = .outputSpy; default: self = .input }
    }
}
