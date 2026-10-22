# CLR MIDI Monitor 1.1.0

Adds a receive-only OSC tab alongside MIDI. Both captures have independent On/Off controls and history, shared across app windows. Active-tab export is available from File → Export Capture.

OSC uses a user-selected, exclusively bound IPv4 UDP port. Default is This Mac only at 127.0.0.1:9001; Network must be selected explicitly. Occupied ports are refused. No forwarding, replies, discovery, port sharing or existing routing changes.

The OSC interface uses the same CLR layout: collapsible Options sidebar, framed latest-event fields, searchable history, Inspect and red OFF overlay. Decodes messages and bounded nested bundles; shows sender, address, types, values, original bundle timetags and raw packet data. Supports JSON export including filtered events.

36 tests pass, including isolated UDP exclusivity, continued original-listener delivery, no-reply and bounded-queue checks. Native loopback capture/inspection/export verified. See docs/OSC-VALIDATION.md for evidence and practical limits.

macOS 13+, Apple Silicon. Ad-hoc signed, not Apple-notarized. PolyForm Noncommercial 1.0.0. A dedicated unused port is required; this does not sniff traffic sent to other apps. No TCP/IPv6, multicast discovery, OSCQuery or forwarding. History is bounded; UDP/network losses remain possible.
