import XCTest
import Darwin
@testable import OSCCore

final class OSCReceiverTests: XCTestCase {
    private func send(_ data: Data, to port: UInt16, fd: Int32) throws {
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        let sent = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                data.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, addr, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        XCTAssertEqual(sent, data.count)
    }
    private func poll(_ receiver: OSCReceiver) -> [OSCDatagram] {
        let end = Date().addingTimeInterval(1)
        while Date() < end {
            let batch = receiver.drain()
            if !batch.packets.isEmpty { return batch.packets }
            usleep(10_000)
        }
        return []
    }
    func testOccupiedPortRefusedAndOriginalStillReceives() throws {
        let original = OSCReceiver(); defer { original.stop() }
        let port = try original.start(port: 0)
        let competitor = OSCReceiver(); defer { competitor.stop() }
        XCTAssertThrowsError(try competitor.start(port: port))
        XCTAssertThrowsError(try competitor.start(port: port, network: true))
        let sender = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP); defer { close(sender) }
        let data = oscString("/still/working") + oscString(",T")
        try send(data, to: port, fd: sender)
        XCTAssertEqual(poll(original).first?.data, data)
        original.stop()
        XCTAssertEqual(try competitor.start(port: port), port)
    }
    func testExistingReusableSocketIsNotShared() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP); defer { close(fd) }
        var yes: Int32 = 1
        XCTAssertEqual(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)), 0)
        XCTAssertEqual(setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size)), 0)
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = UInt32(INADDR_ANY).bigEndian
        XCTAssertEqual(withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }, 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }, 0)
        let receiver = OSCReceiver(); defer { receiver.stop() }
        XCTAssertThrowsError(try receiver.start(port: UInt16(bigEndian: address.sin_port)))
        XCTAssertThrowsError(try receiver.start(port: UInt16(bigEndian: address.sin_port), network: true))
    }
    func testWildcardReservationAlsoRefusesSpecificBind() throws {
        let all = OSCReceiver(); defer { all.stop() }
        let port = try all.start(port: 0, network: true)
        let local = OSCReceiver(); defer { local.stop() }
        XCTAssertThrowsError(try local.start(port: port))
    }
    func testReceivesSenderAndDoesNotReply() throws {
        let receiver = OSCReceiver(); defer { receiver.stop() }
        let port = try receiver.start(port: 0)
        let sender = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP); defer { close(sender) }
        _ = fcntl(sender, F_SETFL, O_NONBLOCK)
        let data = bundle([oscString("/cue") + oscString(",i") + word(4)])
        try send(data, to: port, fd: sender)
        let packets = poll(receiver)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets.first?.sender, "127.0.0.1")
        XCTAssertEqual(packets.first?.localPort, port)
        XCTAssertGreaterThan(packets.first?.senderPort ?? 0, 0)
        XCTAssertEqual(try OSCDecoder.decode(packets[0].data)[0].arguments, ["4"])
        var byte: UInt8 = 0
        XCTAssertEqual(recv(sender, &byte, 1, 0), -1)
        XCTAssertEqual(errno, EAGAIN)
        receiver.stop()
        XCTAssertTrue(receiver.drain().packets.isEmpty)
    }
    func testQueueBoundAndClear() throws {
        let receiver = OSCReceiver(); defer { receiver.stop() }
        let port = try receiver.start(port: 0)
        let sender = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP); defer { close(sender) }
        for _ in 0..<12 {
            for _ in 0..<32 { try send(oscString("/test") + oscString(","), to: port, fd: sender) }
            usleep(20_000)
        }
        usleep(30_000)
        let batch = receiver.drain()
        XCTAssertLessThanOrEqual(batch.packets.count, 32)
        XCTAssertGreaterThan(batch.dropped, 0)
        receiver.clear()
        XCTAssertEqual(receiver.drain().dropped, 0)
        XCTAssertTrue(receiver.drain().packets.isEmpty)
    }
}
