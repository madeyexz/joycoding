#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/.build/KeyReceiver.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$ROOT/tools/keyreceiver/main.swift" -framework AppKit \
  -o "$APP/Contents/MacOS/KeyReceiver"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>JoyCoding Key Receiver</string>
  <key>CFBundleDisplayName</key><string>JoyCoding Key Receiver</string>
  <key>CFBundleIdentifier</key><string>dev.joycoding.proofreceiver</string>
  <key>CFBundleExecutable</key><string>KeyReceiver</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "$APP"
