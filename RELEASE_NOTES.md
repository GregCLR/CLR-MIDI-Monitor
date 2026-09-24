# CLR MIDI Monitor 1.0

First public release of the native Apple Silicon macOS application.

Includes source/destination selection with All checkboxes; bundled, user-initiated output-driver installation; direct virtual MIDI reception; a compact latest-event row and shared history; format/category filters; Inspect with raw UMP; JSON export in the File menu; a collapsible Options sidebar; a red OFF overlay; and an offline manual in the Help menu.

Multiple windows remain available and share one capture session. Export includes all retained events, regardless of display filters.

## Distribution notes

This build is ad-hoc signed, not Apple Developer ID signed or notarized. macOS may block downloaded copies. Source and local build instructions are provided. The output driver is optional for inputs/direct reception, is bundled with the app and never installs automatically or forces a MIDI-server restart.

## Known limits

MIDI 2.0 semantic decoding, SysEx reassembly, capture import/session reopening and Intel binaries are not included. Sender-app names are not supplied by CoreMIDI output observation; OUT rows name destinations. Retained history is limited to 10,000 events. Monitoring has finite capacity and CPU overhead.

## License

Source-available under PolyForm Noncommercial 1.0.0. Commercial-use permission is not granted. Public visibility does not grant write access to the original repository.

## Validation

21 unit tests pass, plus isolated driver overload/memory-safety and Swift IPC tests. CoreMIDI output to Kenton has been reported working by the owner. The release-session controlled live probe did not send anything because another monitor owned the driver subscription; broad live/stage qualification and CPU benchmarks remain outstanding.

Only one app process runs per user, including copies launched from other folders. A second launch activates the existing app. File → New Window still opens another view of the shared capture.
