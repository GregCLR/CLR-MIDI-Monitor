# OSC 1.1.0 validation — 22 October 2026

36 Swift tests pass: 24 existing MIDI/installer/instance tests and 12 OSC tests. Release compilation and deep strict ad-hoc signature verification pass.

OSC tests cover big-endian scalar/string/blob decoding; arrays and zero-payload tags; nested bundle order and original timetags; empty bundles; malformed/truncated packets, padding, unsupported types, complexity limits and a deterministic malformed corpus. Receiver tests use test-owned ephemeral loopback endpoints only. They verify exclusive binding (including wildcard and an already-reusable socket), original-listener delivery after a failed competing bind, release/rebind on stop, queue bounds/clear, sender metadata and no response to the test sender.

Native SwiftUI verification: MIDI starts Off and OSC starts Off. The OSC tab matches the dark CLR sidebar, compact framed latest row, history and Inspect layout. A synthetic 80-byte loopback bundle delivered /test/fader/1 (float 0.75) and /test/cue (integer 12, string Ready, true). Both events survived switching tabs. Inspect displayed the correct sender, local port, immediate timetag and original packet. Command-Shift-E opened OSC export for the active tab; saved JSON was read back and verified (OSC-loopback-validation.json). No MIDI capture was started, hardware routes changed, or OSC LAN traffic sent.

Source audit: the production OSCCore receiver has no send/sendto/sendmsg/connect, SO_REUSEADDR/SO_REUSEPORT setup, multicast membership or discovery calls. Test sending exists only in tests. OSC reception binds only after Monitoring On. It defaults to loopback, with explicit IPv4 network mode.

Limits: this does not prove zero overhead or qualify every network/show setup. UDP can lose data before the app queue; queue-drop counts exclude kernel/network loss. A running listener reserves its selected endpoint, so choose a dedicated spare port. Network mode and firewall behavior on a second physical Mac were not exercised. No TCP, IPv6, OSCQuery, routing or forwarding is provided. Malformed/unsupported packets remain visible as invalid events, with original packet data exportable.
