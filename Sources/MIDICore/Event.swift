import Foundation

public enum CapturePath: String, Codable, Sendable { case input = "IN", virtual = "VIRTUAL", outputSpy = "OUT" }

public struct CapturedPacket: Sendable {
    public let endpoint: UInt32
    public let path: CapturePath
    public let timestamp: UInt64
    public let receivedAt: UInt64
    public let words: [UInt32]
    public init(endpoint: UInt32, path: CapturePath, timestamp: UInt64, receivedAt: UInt64, words: [UInt32]) {
        self.endpoint = endpoint; self.path = path; self.timestamp = timestamp
        self.receivedAt = receivedAt; self.words = words
    }
}

public struct MIDIEvent: Identifiable, Codable {
    public var id = UUID()
    public let endpoint: UInt32
    public let endpointName: String
    public let path: CapturePath
    public let timestamp: UInt64
    public let receivedAt: UInt64
    public let group: Int
    public let channel: Int?
    public let kind: String
    public let detail: String
    public let words: [UInt32]
    public enum Category { case voice, systemCommon, systemExclusive, realTime, other }
    public var category: Category {
        guard kind != "Malformed", let word = words.first else { return .other }
        let type = word >> 28
        let status = (word >> 16) & 0xFF
        switch type {
        case 2, 4: return .voice
        case 1:
            if status >= 0xF8 { return .realTime }
            return [0xF1, 0xF2, 0xF3, 0xF6].contains(status) ? .systemCommon : .other
        case 3: return .systemExclusive
        case 5: return ((word >> 20) & 0xF) <= 3 ? .systemExclusive : .other
        default: return .other
        }
    }
    public var hex: String { words.map { String(format: "%08X", $0) }.joined(separator: " ") }
}

/// MIDI 1.0 UMP decoding. Other message types remain visible as raw UMP.
/// SysEx fragments are deliberately not presented as complete messages.
public enum UMPDecoder {
    private static let lengths = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
    public static func decode(_ packet: CapturedPacket, name: String) -> [MIDIEvent] {
        var result: [MIDIEvent] = [], offset = 0
        while offset < packet.words.count {
            let word = packet.words[offset], type = Int(word >> 28)
            let length = lengths[type], end = min(offset + length, packet.words.count)
            let raw = Array(packet.words[offset..<end])
            let status = Int((word >> 16) & 255), a = Int((word >> 8) & 127), b = Int(word & 127)
            var kind = "UMP type \(type)", detail = "Raw packet", channel: Int?
            if raw.count != length { kind = "Malformed"; detail = "Truncated UMP: expected \(length) words" }
            else if type == 2 {
                channel = (status & 15) + 1
                let note = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][a % 12] + "\(a / 12 - 1)"
                switch status >> 4 {
                case 8: kind = "Note Off"; detail = "\(note) (\(a)) · release \(b)"
                case 9: kind = b == 0 ? "Note Off" : "Note On"; detail = "\(note) (\(a)) · velocity \(b)" + (b == 0 ? " · Note On zero" : "")
                case 10: kind = "Poly Pressure"; detail = "\(note) · pressure \(b)"
                case 11: kind = "Control Change"; detail = "CC \(a) · value \(b)" + (a == 64 ? (b >= 64 ? " · sustain on" : " · sustain off") : "")
                case 12: kind = "Program Change"; detail = "Program \(a) (0–127)"
                case 13: kind = "Channel Pressure"; detail = "Pressure \(a)"
                case 14: kind = "Pitch Bend"; detail = "\((b << 7 | a) - 8192)"
                default: kind = "Malformed"; detail = "Invalid channel voice status"; channel = nil
                }
            } else if type == 1 {
                kind = [0xF1: "MTC Quarter Frame", 0xF2: "Song Position", 0xF3: "Song Select", 0xF6: "Tune Request", 0xF8: "Clock", 0xFA: "Start", 0xFB: "Continue", 0xFC: "Stop", 0xFE: "Active Sensing", 0xFF: "Reset"][status] ?? "System"
                detail = String(format: "%02X %02X %02X", status, a, b)
            } else if type == 3 { kind = "SysEx7 fragment"; detail = "Raw UMP · reassembly pending" }
            else if type == 4 { kind = "MIDI 2.0"; detail = "Raw UMP · semantic decoding pending" }
            result.append(MIDIEvent(endpoint: packet.endpoint, endpointName: name, path: packet.path,
                timestamp: packet.timestamp, receivedAt: packet.receivedAt, group: Int((word >> 24) & 15) + 1,
                channel: channel, kind: kind, detail: detail, words: raw))
            offset = end
        }
        return result
    }
}

