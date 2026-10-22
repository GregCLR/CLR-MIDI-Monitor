import SwiftUI
import AppKit

struct OSCView: View {
    @ObservedObject var model: OSCModel
    @AppStorage("oscSidebarVisible") private var sidebarVisible = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { sidebarVisible.toggle() } label: {
                    Label("Options", systemImage: "sidebar.left").font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18).frame(height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).frame(width: sidebarVisible ? 301 : 128, alignment: .leading)
                    .accessibilityLabel(sidebarVisible ? "Options — Hide sidebar" : "Options — Show sidebar")
                HStack(spacing: 18) {
                    WebsiteLogo()
                    Text("OSC MONITOR").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Toggle("Monitoring", isOn: Binding(get: { model.running }, set: { if $0 != model.running { model.toggle() } }))
                        .toggleStyle(MonitoringSwitch())
                    Button("Export") { model.export() }.disabled(model.events.isEmpty)
                }.padding(.leading, 16).padding(.trailing, 20)
            }.padding(.vertical, 14)
            Divider().overlay(CLR.line)
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar.frame(width: 300)
                    Rectangle().fill(CLR.line).frame(width: 1)
                }
                stream.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = model.error {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button("Dismiss") { model.error = nil } }.padding(12)
            }
        }.background(Color(white: 0.035)).tint(CLR.amber).frame(minWidth: 1120, minHeight: 680)
    }
    private func title(_ label: String) -> some View {
        Text(label).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(CLR.amber)
    }
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title("RECEIVE OSC")
                VStack(alignment: .leading, spacing: 6) {
                    Text("UDP port").font(.caption).foregroundStyle(.secondary)
                    TextField("1024–65535", text: $model.port).textFieldStyle(.roundedBorder)
                        .disabled(model.running).accessibilityLabel("OSC UDP port")
                }
                Picker("Listen on", selection: $model.network) {
                    Text("This Mac only").tag(false)
                    Text("Network (IPv4)").tag(true)
                }.disabled(model.running)
                Text(model.running ? "Listening · \(model.network ? "all IPv4 interfaces" : "127.0.0.1"):\(model.port)" : "Not listening")
                    .font(.caption).foregroundStyle(model.running ? Color.green : Color.secondary)
                Text(model.network ? "Send OSC to this Mac’s IPv4 address and the port above." : "Send OSC to 127.0.0.1 and the port above.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Use a spare port. This receives messages addressed here; it does not observe another app’s port or forward traffic.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider().overlay(CLR.line)
                title("DISPLAY")
                Toggle("Display filters", isOn: $model.filtersEnabled).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Sender IP or port", text: $model.senderFilter).textFieldStyle(.roundedBorder)
                    TextField("Search address, type or value", text: $model.search).textFieldStyle(.roundedBorder)
                    Toggle("Hide invalid packets", isOn: $model.hideInvalid).toggleStyle(.checkbox)
                }.disabled(!model.filtersEnabled)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(CLR.sidebar)
    }
    private var stream: some View {
        GeometryReader { geo in
            let width = max(780, geo.size.width - 32)
            let visible = model.visibleEvents
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    title(model.filtersEnabled && (!model.search.isEmpty || !model.senderFilter.isEmpty || model.hideInvalid) ? "LAST OBSERVED EVENT · FILTERED" : "LAST OBSERVED EVENT")
                    Spacer(); Button("Clear") { model.clear() }
                }.padding(.bottom, 10)
                columns(width)
                row(visible.last, width, highlighted: true).padding(.bottom, 6)
                Divider().overlay(CLR.line)
                title("HISTORY").padding(.vertical, 10)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { event in
                            row(event, width)
                                .background(model.selection == event.id ? CLR.amber.opacity(0.13) : Color.clear)
                                .contentShape(Rectangle()).onTapGesture { model.selection = event.id }
                                .contextMenu {
                                    Button("Copy event") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("\(model.time(event))\t\(event.source)\t\(event.address)\t\(event.arguments)", forType: .string)
                                    }
                                }
                            Divider().opacity(0.3)
                        }
                    }
                }.overlay {
                    if !model.running {
                        ZStack {
                            Color.red.opacity(0.16)
                            Text("OFF").font(.system(size: 40, weight: .semibold)).tracking(4).foregroundStyle(Color.red.opacity(0.9))
                        }.allowsHitTesting(false).accessibilityLabel("OSC monitoring off")
                    } else if visible.isEmpty {
                        Text(model.events.isEmpty ? "Waiting for OSC" : "No matching events").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                inspector.padding(.top, 10)
                HStack {
                    Text("\(model.events.count) retained · \(visible.count) shown")
                    Spacer()
                    Text("\(model.invalid) invalid · \(model.dropped) queue drops · \(model.evicted) aged out")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(16)
        }
    }
    private func widths(_ width: CGFloat) -> [CGFloat] { [112, 180, (width - 426) * 0.43, 70, (width - 426) * 0.57, 64] }
    private func columns(_ width: CGFloat) -> some View {
        let labels = ["Time", "Sender", "Address", "Types", "Arguments", "Bytes"]
        let sizes = widths(width)
        return HStack(spacing: 0) {
            ForEach(0..<labels.count, id: \.self) { i in
                Text(labels[i]).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).frame(width: sizes[i], height: 28, alignment: .leading)
            }
        }
    }
    private func row(_ event: OSCEvent?, _ width: CGFloat, highlighted: Bool = false) -> some View {
        let values = [event.map { model.time($0) } ?? "—", event?.source ?? "—", event?.address ?? "—", event?.message?.types ?? "—", event?.arguments ?? "—", event.map { String($0.packet.count) } ?? "—"]
        let sizes = widths(width)
        return HStack(spacing: 0) {
            ForEach(0..<values.count, id: \.self) { i in
                Text(String(values[i].prefix(512))).font(CLR.rowFont).lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 6).frame(width: sizes[i], height: 28, alignment: .leading)
                    .background {
                        if highlighted {
                            RoundedRectangle(cornerRadius: 4).fill(CLR.amber.opacity(0.08))
                                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(CLR.amber.opacity(0.32), lineWidth: 1) }
                                .padding(.horizontal, 2)
                        }
                    }.help(String(values[i].prefix(2048)))
            }
        }.accessibilityElement(children: .combine)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("INSPECT")
            if let event = model.events.first(where: { $0.id == model.selection }) {
                HStack(alignment: .top, spacing: 20) {
                    field("Sender → local UDP port", "\(event.source) → \(event.localPort)")
                    field("Address / types", "\(event.address)  \(event.message?.types ?? "")")
                    field("Bundle NTP tags (outer → inner)", event.message?.timeTags.joined(separator: " → ").nilIfEmpty ?? "—")
                }
                Text(String(event.arguments.prefix(4096))).font(CLR.rowFont).lineLimit(3).textSelection(.enabled)
                Text("Raw packet · \(event.packet.count) bytes\(event.packet.count > 256 ? " · first 256 shown" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(event.packet.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " "))
                    .font(.system(size: 11, design: .monospaced)).lineLimit(3).textSelection(.enabled)
            } else { Text("Select an event from the history").font(.caption).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(CLR.line)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(value.prefix(512))).font(CLR.rowFont).lineLimit(2).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
