import Foundation
import Darwin

public struct OSCDatagram {
    public let data: Data
    public let sender: String
    public let senderPort: UInt16
    public let receivedAt: Date
    public let localPort: UInt16
}

/// IPv4 UDP receiver. No send API, reuse options, discovery or multicast joins.
/// All socket operations are serialized; buffers and work per tick are bounded.
public final class OSCReceiver {
    private let queue = DispatchQueue(label: "com.clr.monitor.osc.receive", qos: .utility)
    private var socketFD: Int32 = -1
    private var timer: DispatchSourceTimer?
    private var pending: [OSCDatagram] = []
    private var pendingBytes = 0
    private var dropped = 0
    private var failure: String?
    private var localPort: UInt16 = 0
    private let queueKey = DispatchSpecificKey<UInt8>()
    public init() { queue.setSpecific(key: queueKey, value: 1) }
    deinit { stop() }

    @discardableResult
    public func start(port: UInt16, network: Bool = false) throws -> UInt16 {
        try queue.sync {
            guard socketFD < 0 else { throw OSCDecodeError.invalid("OSC is already monitoring") }
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { throw socketError() }
            var accepted = false
            defer { if !accepted { close(fd) } }
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw socketError() }
            // Intentionally do NOT set SO_REUSEADDR or SO_REUSEPORT. An occupied
            // endpoint must fail rather than split/steal another app's datagrams.
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = (network ? UInt32(INADDR_ANY) : UInt32(INADDR_LOOPBACK)).bigEndian
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard result == 0 else {
                if errno == EADDRINUSE { throw OSCDecodeError.invalid("UDP port \(port) is already in use. Choose a different port; the existing listener was not changed.") }
                throw socketError()
            }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
            }
            guard nameResult == 0 else { throw socketError() }
            socketFD = fd
            localPort = UInt16(bigEndian: address.sin_port)
            pending.removeAll(); pendingBytes = 0; dropped = 0; failure = nil
            accepted = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.receive() }
            self.timer = timer
            timer.resume()
            return localPort
        }
    }
    public func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil { stopOnQueue() }
        else { queue.sync { stopOnQueue() } }
    }
    private func stopOnQueue() {
        timer?.cancel(); timer = nil
        if socketFD >= 0 { close(socketFD); socketFD = -1 }
        pending.removeAll(); pendingBytes = 0
    }
    public func clear() {
        queue.sync { pending.removeAll(); pendingBytes = 0; dropped = 0 }
    }
    public func drain() -> (packets: [OSCDatagram], dropped: Int, error: String?) {
        queue.sync {
            let packets = Array(pending.prefix(32))
            pending.removeFirst(packets.count)
            pendingBytes -= packets.reduce(0) { $0 + $1.data.count }
            return (packets, dropped, failure)
        }
    }
    private func socketError() -> Error { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    private func receive() {
        guard socketFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65_535)
        for _ in 0..<64 {
            var sender = sockaddr_in()
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    buffer.withUnsafeMutableBytes { recvfrom(socketFD, $0.baseAddress, $0.count, 0, addr, &size) }
                }
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                failure = String(cString: strerror(errno)); timer?.cancel(); timer = nil
                close(socketFD); socketFD = -1
                return
            }
            guard pending.count < 256, pendingBytes + count <= 2_097_152 else { dropped += 1; continue }
            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            _ = inet_ntop(AF_INET, &sender.sin_addr, &ip, socklen_t(ip.count))
            pending.append(OSCDatagram(data: Data(buffer.prefix(count)), sender: String(cString: ip), senderPort: UInt16(bigEndian: sender.sin_port), receivedAt: Date(), localPort: localPort))
            pendingBytes += count
        }
    }
}
