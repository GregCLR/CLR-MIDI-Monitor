import Foundation

public struct OSCMessage: Equatable, Codable {
    public let address: String
    public let types: String
    public let arguments: [String]
    /// Outer-to-inner bundle time tags, in their original NTP representation.
    public let timeTags: [String]
    public let isBundle: Bool
}

public enum OSCDecodeError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public enum OSCDecoder {
    /// No dispatch, execution or timetag scheduling: decode only, on arrival.
    public static func decode(_ data: Data) throws -> [OSCMessage] {
        guard !data.isEmpty, data.count <= 65_507, data.count % 4 == 0 else {
            throw OSCDecodeError.invalid("Invalid OSC packet length")
        }
        var budget = 256
        return try packet(Array(data), tags: [], depth: 0, budget: &budget)
    }
    private static func packet(_ bytes: [UInt8], tags: [String], depth: Int, budget: inout Int) throws -> [OSCMessage] {
        guard depth <= 16, budget > 0 else { throw OSCDecodeError.invalid("OSC bundle complexity limit exceeded") }
        budget -= 1
        var reader = Reader(bytes: bytes)
        let address = try reader.string()
        if address == "#bundle" {
            let tag = String(format: "%016llX", try reader.u64())
            var result: [OSCMessage] = []
            while reader.remaining > 0 {
                let size = Int(try reader.u32())
                guard size > 0, size % 4 == 0 else { throw OSCDecodeError.invalid("Invalid bundle element size") }
                let child = try reader.take(size)
                result += try packet(child, tags: tags + [tag], depth: depth + 1, budget: &budget)
            }
            if result.isEmpty { result.append(OSCMessage(address: "#bundle", types: "", arguments: [], timeTags: tags + [tag], isBundle: true)) }
            return result
        }
        guard address.hasPrefix("/") else { throw OSCDecodeError.invalid("OSC address must begin with /") }
        let types = try reader.string()
        guard types.first == ",", types.count <= 257 else { throw OSCDecodeError.invalid("Missing or oversized OSC type tag string") }
        var values: [String] = []
        var arrays = 0
        for type in types.dropFirst() {
            switch type {
            case "i": values.append(String(Int32(bitPattern: try reader.u32())))
            case "f": values.append(String(Float(bitPattern: try reader.u32())))
            case "s", "S": values.append(String(reflecting: try reader.string()))
            case "b":
                let size = Int(try reader.u32())
                let bytes = try reader.take(size)
                try reader.padding(size)
                values.append("blob[\(size)] " + bytes.prefix(32).map { String(format: "%02X", $0) }.joined() + (size > 32 ? "…" : ""))
            case "h": values.append(String(Int64(bitPattern: try reader.u64())))
            case "d": values.append(String(Double(bitPattern: try reader.u64())))
            case "t": values.append(String(format: "NTP:%016llX", try reader.u64()))
            case "c":
                let value = try reader.u32()
                guard value < 128, let scalar = UnicodeScalar(value) else { throw OSCDecodeError.invalid("Invalid OSC character") }
                values.append(String(reflecting: String(scalar)))
            case "r", "m": values.append(String(format: "0x%08X", try reader.u32()))
            case "T": values.append("true")
            case "F": values.append("false")
            case "N": values.append("nil")
            case "I": values.append("infinitum")
            case "[": arrays += 1; guard arrays <= 16 else { throw OSCDecodeError.invalid("Array nesting limit exceeded") }; values.append("[")
            case "]": arrays -= 1; guard arrays >= 0 else { throw OSCDecodeError.invalid("Unbalanced OSC array") }; values.append("]")
            default: throw OSCDecodeError.invalid("Unsupported OSC type tag: \(type)")
            }
        }
        guard arrays == 0, reader.remaining == 0 else { throw OSCDecodeError.invalid("Unbalanced array or trailing OSC bytes") }
        return [OSCMessage(address: address, types: types, arguments: values, timeTags: tags, isBundle: false)]
    }
    private struct Reader {
        let bytes: [UInt8]
        var cursor = 0
        var remaining: Int { bytes.count - cursor }
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= remaining else { throw OSCDecodeError.invalid("Truncated OSC packet") }
            defer { cursor += count }
            return Array(bytes[cursor..<(cursor + count)])
        }
        mutating func u32() throws -> UInt32 { try take(4).reduce(0) { ($0 << 8) | UInt32($1) } }
        mutating func u64() throws -> UInt64 { try take(8).reduce(0) { ($0 << 8) | UInt64($1) } }
        mutating func padding(_ length: Int) throws {
            guard try take((4 - length % 4) % 4).allSatisfy({ $0 == 0 }) else { throw OSCDecodeError.invalid("Invalid OSC padding") }
        }
        mutating func string() throws -> String {
            guard let end = bytes[cursor...].firstIndex(of: 0) else { throw OSCDecodeError.invalid("Unterminated OSC string") }
            let count = end - cursor
            let content = try take(count)
            _ = try take(1)
            try padding(count + 1)
            guard let value = String(bytes: content, encoding: .utf8) else { throw OSCDecodeError.invalid("Invalid OSC string encoding") }
            return value
        }
    }
}
