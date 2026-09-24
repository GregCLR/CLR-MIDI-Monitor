#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p work
xcrun clang -std=c11 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer -framework CoreMIDI -framework CoreFoundation -I Sources/CaptureTransport/include Driver/Tests.c Sources/CaptureTransport/CaptureTransport.c -o work/driver-tests
ASAN_OPTIONS=detect_leaks=0 work/driver-tests
# Production driver must have no MIDI transmission, routing, endpoint creation,
# or server-restart imports. A new import fails this guard.
if nm -u 'outputs/CLR Output Monitor.plugin/Contents/MacOS/CLRSpy' | rg '_(MIDISend|MIDIReceived|MIDIThru|MIDISourceCreate|MIDIDestinationCreate|MIDIRestart)'; then
    echo 'FAIL: forbidden routing/transmission import'; exit 1
fi
