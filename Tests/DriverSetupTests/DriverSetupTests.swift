import XCTest
@testable import MIDICapture
final class DriverSetupTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func fixture() throws -> URL {
        let source = root.appendingPathComponent("Bundled.plugin")
        let contents = source.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": OutputDriverInstaller.identifier, "CFBundleExecutable": "CLRSpy"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let executable = contents.appendingPathComponent("MacOS/CLRSpy")
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return source
    }
    func testSignedDriverInstallInTemporaryDirectory() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = project.appendingPathComponent("outputs/CLR Output Monitor.plugin")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("Run scripts/build-driver.sh to test the signed driver fixture") }
        let installer = OutputDriverInstaller(source: source, directory: root.appendingPathComponent("Audio/MIDI Drivers"))
        try installer.install()
        XCTAssertTrue(installer.isInstalled)
    }
    func testInstallStateAndRepeatInstall() throws {
        let source = try fixture(), directory = root.appendingPathComponent("Audio/MIDI Drivers")
        var checks = 0
        let installer = OutputDriverInstaller(source: source, directory: directory) { _ in checks += 1 }
        XCTAssertFalse(installer.isInstalled)
        try installer.install()
        XCTAssertTrue(installer.isInstalled)
        try installer.install()
        XCTAssertEqual(checks, 4)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path), ["MIDI Drivers"])
    }
    func testMissingBundleDoesNotInstall() {
        let installer = OutputDriverInstaller(source: nil, directory: root.appendingPathComponent("drivers")) { _ in }
        XCTAssertThrowsError(try installer.install()); XCTAssertFalse(installer.isInstalled)
    }
    func testFailedValidationDoesNotPublishPartialPlugin() throws {
        let source = try fixture(), directory = root.appendingPathComponent("Audio/drivers")
        var calls = 0
        let installer = OutputDriverInstaller(source: source, directory: directory) { _ in
            calls += 1
            if calls == 2 { throw NSError(domain: "test", code: 1) }
        }
        XCTAssertThrowsError(try installer.install()); XCTAssertFalse(installer.isInstalled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path), [])
    }
    func testExistingUnrelatedItemPreserved() throws {
        let source = try fixture(), directory = root.appendingPathComponent("drivers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("CLR Output Monitor.plugin")
        let original = Data("leave untouched".utf8); try original.write(to: destination)
        let installer = OutputDriverInstaller(source: source, directory: directory) { _ in }
        XCTAssertThrowsError(try installer.install()); XCTAssertFalse(installer.isInstalled)
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }
}
