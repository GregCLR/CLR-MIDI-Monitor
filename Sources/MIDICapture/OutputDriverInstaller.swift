import Foundation
import Security

/// Copies only the bundled CLR plugin, with validation before atomic publication.
/// Does not restart CoreMIDI, download code, or change routing.
public struct OutputDriverInstaller {
    public static let identifier = "com.clr.midimonitor.driver"
    private let source: URL?
    private let directory: URL
    private let verify: (URL) throws -> Void
    public init(bundle: Bundle = .main) {
        source = bundle.url(forResource: "CLR Output Monitor", withExtension: "plugin")
        directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/MIDI Drivers", isDirectory: true)
        verify = Self.verifySignature
    }
    init(source: URL?, directory: URL) {
        self.source = source; self.directory = directory; self.verify = Self.verifySignature
    }
    // Alternate paths and verifier let tests exercise installation without touching CoreMIDI.
    init(source: URL?, directory: URL, verify: @escaping (URL) throws -> Void) {
        self.source = source; self.directory = directory; self.verify = verify
    }
    private var destination: URL { directory.appendingPathComponent("CLR Output Monitor.plugin", isDirectory: true) }
    public var isInstalled: Bool { (try? Self.validateBundle(destination)) != nil }
    public func install() throws {
        let files = FileManager.default
        guard let source else { throw failure("The output monitor is missing from this app. Reinstall the complete app bundle.") }
        try Self.validateBundle(source)
        try verify(source)
        // Never replace a pre-existing file, plugin or symbolic link.
        if (try? files.attributesOfItem(atPath: destination.path)) != nil {
            guard isInstalled else { throw failure("A different or incomplete item already exists at the output monitor location. It was left unchanged.") }
            try verify(destination)
            return
        }
        let parent = directory.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".CLR-output-install-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(destination.lastPathComponent)
        try files.copyItem(at: source, to: staged)
        try Self.validateBundle(staged)
        try verify(staged)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try files.moveItem(at: staged, to: destination)
    }
    private static func validateBundle(_ url: URL) throws {
        let files = FileManager.default
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              plist["CFBundleIdentifier"] as? String == identifier,
              plist["CFBundleExecutable"] as? String == "CLRSpy",
              files.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/CLRSpy").path) else {
            throw failure("The output monitor bundle is invalid.")
        }
    }
    private static func verifySignature(_ url: URL) throws {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard created == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw failure("The output monitor signature could not be verified. Nothing was installed.")
        }
    }
    private static func failure(_ message: String) -> Error {
        NSError(domain: "CLR.DriverSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func failure(_ message: String) -> Error { Self.failure(message) }
}
