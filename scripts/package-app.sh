#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift run VoiceOverlayTestRunner
swift build -c release
BIN="$(swift build -c release --show-bin-path)/VoiceOverlay"
APP="dist/VoiceOverlay.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VoiceOverlay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/VoiceOverlay"
codesign -s - --force --entitlements Resources/VoiceOverlay.entitlements "$APP" >/dev/null
echo "Built $APP"
echo "Open it with: open \"$APP\""
echo "Then enable Microphone + Accessibility for Voice Overlay."
