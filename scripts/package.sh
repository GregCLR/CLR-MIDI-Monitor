#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
scripts/build-driver.sh
swift build --scratch-path work/build -c release --product CLRMonitor
app="outputs/CLR MIDI Monitor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp work/build/release/CLRMonitor "$app/Contents/MacOS/CLRMonitor"
cp -R work/build/release/CLRMIDIMonitor_CLRMonitor.bundle "$app/Contents/Resources/"
cp Sources/CLRMonitor/Resources/CLRMonitorIcon.icns "$app/Contents/Resources/"
ditto "outputs/CLR Output Monitor.plugin" "$app/Contents/Resources/CLR Output Monitor.plugin"
cp LICENSE.md NOTICE "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CLRMonitor</string>
<key>CFBundleIdentifier</key><string>com.clr.midimonitor</string>
<key>CFBundleName</key><string>CLR MIDI Monitor</string>
<key>CFBundleDisplayName</key><string>CLR MIDI Monitor</string>
<key>CFBundleIconFile</key><string>CLRMonitorIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>100</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
touch "$app"
echo "Built $app"
