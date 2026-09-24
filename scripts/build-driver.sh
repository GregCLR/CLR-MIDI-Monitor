#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
driver='outputs/CLR Output Monitor.plugin'
mkdir -p "$driver/Contents/MacOS"
xcrun clang -std=c11 -O2 -mmacosx-version-min=13.0 -bundle -framework CoreMIDI -framework CoreFoundation -I Sources/CaptureTransport/include Driver/CLRSpy.c Sources/CaptureTransport/CaptureTransport.c -o "$driver/Contents/MacOS/CLRSpy"
cat > "$driver/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.clr.midimonitor.driver</string>
<key>CFBundleName</key><string>CLR Output Monitor</string>
<key>CFBundleExecutable</key><string>CLRSpy</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFPlugInDynamicRegistration</key><false/>
<key>CFPlugInFactories</key><dict><key>C1DE730A-E471-4535-9753-6634A88AF941</key><string>CLRSpyFactory</string></dict>
<key>CFPlugInTypes</key><dict><key>ECDE9574-0FE4-11D4-BB1A-0050E4CEA526</key><array><string>C1DE730A-E471-4535-9753-6634A88AF941</string></array></dict>
</dict></plist>
PLIST
codesign --force --sign - "$driver"
