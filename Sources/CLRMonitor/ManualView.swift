import SwiftUI
import WebKit

struct MonitorHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("CLR MIDI Monitor Help") { openWindow(id: "user-guide") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct ManualView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        let bundled = Bundle.main.url(forResource: "CLRMIDIMonitor_CLRMonitor", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? .module
        if let url = bundled.url(forResource: "Manual", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<h1>CLR MIDI Monitor Help</h1><p>The guide is missing from this app bundle. Download the complete app.</p>", baseURL: nil)
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
