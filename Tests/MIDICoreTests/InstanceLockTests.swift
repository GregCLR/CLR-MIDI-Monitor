import XCTest
@testable import MIDICore

final class InstanceLockTests: XCTestCase {
    func testExclusiveAndReleasedOnClose() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".lock"
        defer { try? FileManager.default.removeItem(atPath: path) }
        var first = try InstanceLock(path: path)
        XCTAssertNotNil(first)
        XCTAssertNil(try InstanceLock(path: path))
        first = nil
        XCTAssertNotNil(try InstanceLock(path: path))
    }

    func testOtherProcessAndCrashRelease() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".lock"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", "import fcntl,sys,time; f=open(sys.argv[1], 'w'); fcntl.flock(f, fcntl.LOCK_EX); print('ready', flush=True); time.sleep(30)", path]
        let pipe = Pipe()
        child.standardOutput = pipe
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        XCTAssertFalse(pipe.fileHandleForReading.availableData.isEmpty)
        XCTAssertNil(try InstanceLock(path: path))
        child.terminate()
        child.waitUntilExit()
        XCTAssertNotNil(try InstanceLock(path: path))
    }

    func testFailureIsNotMistakenForAnotherInstance() {
        XCTAssertThrowsError(try InstanceLock(path: "/missing-\(UUID().uuidString)/instance.lock"))
    }
}
