# CLR MIDI Monitor

A native macOS MIDI monitor with a compact latest-event row, searchable history and a detailed inspector.

**Version 1.1.0 · macOS 13+ · Apple Silicon**

## Features

- Monitor hardware and software MIDI sources.
- Observe traffic sent to selected output destinations using the bundled CoreMIDI plugin.
- Receive MIDI directly through `CLR MIDI Monitor — Receive`.
- Select or clear all listed inputs/outputs in one click.
- Show note/controller names or numbers; choose C3/C4 for Middle C.
- Hide voice, System Common, SysEx, clock and active-sensing messages.
- Inspect original UMP words and timestamps; export retained history as JSON.
- Open the offline guide from **Help → CLR MIDI Monitor Help**.
- Open the Custom Live Rigs website from the CLR logo, or right-click it to copy the address.

The monitor does not send, echo or route MIDI. Outputs are identified by destination, not by the sending application. Data kept entirely inside a DAW/plugin may not be visible to CoreMIDI.

## Get started

Open the app, choose Inputs under Options, and turn Monitoring on. The app automatically prepares its bundled output observer before CoreMIDI starts, so there is no separate download or installation step. To observe another app sending MIDI to hardware, select the destination under Outputs.

For direct reception from Ableton Live, enable Receive from software and Monitoring, enable Track for the CLR receive output in Live's MIDI settings, then select it in the track's MIDI To menu. This redirects the track to the monitor; leave the original hardware routing unchanged if you want to observe it under Outputs instead.

Read the [user guide](Sources/CLRMonitor/Resources/Manual.html) for routing, controls, export and troubleshooting.

## Download and trust

The downloadable app is ad-hoc signed and **not Apple-notarized**. macOS may block a downloaded copy. No Developer ID certificate is included in this repository. Developers can build locally from the source below. Do not disable macOS security protections to use the app.

The bundled output observer is prepared automatically before the app initializes CoreMIDI. It never forcibly restarts CoreMIDI. If CoreMIDI was already running when the observer was first prepared, restart the Mac once before testing outputs.

## Build

Requires Xcode with the macOS SDK and Swift 5.9 or newer. No third-party packages are fetched.

```sh
scripts/build-driver.sh
swift test --scratch-path work/build
scripts/package.sh
```

The app is written to `outputs/CLR MIDI Monitor.app`. Optional source artwork regeneration: `swift scripts/render-icon.swift`, then use `iconutil` to rebuild the icon set.

## Tests

```sh
scripts/test-driver.sh
python3 scripts/test-output-adapter.py
```

These driver/adapter tests use a private IPC namespace and an isolated host with CoreMIDI registration stubbed out. They never install a driver, connect to the live MIDI server or send to hardware. `test-driver.sh` enables AddressSanitizer/UndefinedBehaviorSanitizer and audits the production driver's imports for forbidden MIDI transmission/routing APIs.

`OutputLiveProbe` is a separate, explicit live test. It creates and sends only to its own temporary destination and requires the installed driver to be available and not owned by another active app instance. Do not run it during a performance or recording. The monitor itself contains no MIDI sending code; send APIs occur only in the dedicated capture/live test tools.

## Limits

- Capture is retained in memory, capped at 10,000 events; export before quitting. JSON import/session reopening is not implemented.
- Multiple windows share one session. File → Export Capture exports the same retained history from every window, including filtered-out events.
- MIDI 2.0 semantic decoding and SysEx reassembly are not complete. Unsupported data remains inspectable as raw UMP/fragments.
- Queues are bounded. Overload drops monitor copies and reports counters; monitoring has CPU/memory overhead and is not a zero-risk guarantee for every setup.
- No Intel build, notarization or automatic update service is included.

## Repository control

A public repository does not give public users write access. Changes to this repository are controlled by its owner. Public users can read/download the source and may fork it under the applicable license; a fork cannot alter this repository. External contributions are not automatically accepted or merged.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md). This is **source-available, not OSI open source**. Commercial-use permission is not granted; this restriction applies to using the app as well as redistributing or modifying it. See the full license for permitted purposes and exceptions. Copyright notices are in [NOTICE](NOTICE).

Only one app process runs per user, including copies launched from other folders. A second launch activates the existing app. File → New Window still opens another view of the shared capture.

## OSC tab (1.1.0)

Receive-only OSC over IPv4 UDP. Select the OSC tab, enter an unused UDP port (1024–65535), choose This Mac only or Network, then turn Monitoring on. Both protocols start off, run independently, and keep their capture when switching tabs; the top status indicators show both. File export uses the active tab in the frontmost monitor window.

Default reception is 127.0.0.1:9001. For network reception, explicitly select Network and send to this Mac's IPv4 address. The receiver never enables port sharing/reuse, joins multicast, sends, replies or forwards. Occupied endpoints fail without replacing the existing listener. Use a dedicated spare port: while running, the monitor reserves that endpoint and another app cannot bind it. Stop monitoring to release it. It does not sniff another app's traffic. No routing/firewall changes are made. Network mode accepts incoming packets from reachable senders; do not expose it to untrusted networks.

OSC 1.0 messages and nested bundles, core i/f/s/b and h/d/t/S/c/r/m/T/F/N/I/array tags are decoded. Bundle timetags are displayed as original hexadecimal NTP values (1 = immediate); messages are displayed on arrival, never scheduled or executed. Unknown tags/malformed packets appear as invalid packets with raw data. Maximum 16 bundle nesting levels and 256 packet elements/type tags; oversized/overcomplex input is rejected.

Separate OSC latest/history/inspector, sender and address/type/value search, display filters and JSON export. Export retains original datagrams as base64 plus sender/local port/timestamps and decoded fields, including filtered-out events. Bundled messages share arrival time and repeat the parent packet in export. Arrival timestamps are local receipt times, not source timing measurements. History caps at 10,000 events and a conservative 16 MiB content budget; queue caps at 256 packets/2 MiB, drained in bounded batches. Queue drops exclude losses in the OS/network. No TCP, IPv6, multicast discovery, forwarding or OSCQuery. The MIDI capture engine and routing behavior are unchanged.

Decoder reference: https://opensoundcontrol.stanford.edu/spec-1_0.html
