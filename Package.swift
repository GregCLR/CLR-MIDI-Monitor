// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CLRMIDIMonitor", platforms: [.macOS(.v13)],
    products: [.executable(name: "CLRMonitor", targets: ["CLRMonitor"]),
               .executable(name: "MIDICaptureProbe", targets: ["MIDICaptureProbe"])],
    targets: [
        .target(name: "CaptureTransport", linkerSettings: [.linkedFramework("CoreMIDI")]),
        .target(name: "MIDICore", dependencies: ["CaptureTransport"]),
        .target(name: "MIDICapture", dependencies: ["MIDICore"]),
        .executableTarget(name: "OutputLiveProbe", dependencies: ["MIDICapture", "MIDICore"]),
        .executableTarget(name: "OutputSpyProbe", dependencies: ["MIDICapture", "MIDICore"]),
        .executableTarget(name: "MIDICaptureProbe", dependencies: ["MIDICapture", "MIDICore"]),
        .executableTarget(name: "CLRMonitor", dependencies: ["MIDICore", "MIDICapture"], resources: [.process("Resources")]),
        .testTarget(name: "DriverSetupTests", dependencies: ["MIDICapture"]),
        .testTarget(name: "MIDICoreTests", dependencies: ["MIDICore"])
    ]
)
