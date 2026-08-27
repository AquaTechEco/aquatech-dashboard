#!/bin/bash
# Archive AquaTech Weather (iOS + Watch + Widget) with released Xcode 26.6
# toolchain and upload to TestFlight. Same headless recipe as ATEC Daily Log /
# BubbaView: beta macOS can't LAUNCH stable Xcode 26.6 GUI, but its CLI toolchain
# runs fine and builds against the App-Store-accepted iphoneos26.5 SDK.
# NOTE: use -destination 'generic/platform=iOS' (NOT -sdk iphoneos26.5). This app
# embeds a Watch app; -sdk forces the iOS SDK on every target and breaks the watch
# sub-build's WatchKit resolution. -destination lets each target pick its own SDK.
# Requires the watchOS platform installed: xcodebuild -downloadPlatform watchOS.
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEY=~/.appstoreconnect/private_keys/AuthKey_H6R8UKCZJK.p8
KEYID=H6R8UKCZJK
ISSUER=caf71c14-79cf-4075-b614-1096efab3b8c
ARCH=/tmp/AquaTechWeather.xcarchive
EXPORT=/tmp/AquaTechWeather-export

echo "=== [1/2] ARCHIVE (Xcode $(xcodebuild -version | head -1 | awk '{print $2}'), sdk iphoneos26.5) ==="
rm -rf "$ARCH" "$EXPORT"
xcodebuild archive \
  -project AquaTechWeather.xcodeproj -scheme AquaTechWeather -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCH" ONLY_ACTIVE_ARCH=NO \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEYID" -authenticationKeyIssuerID "$ISSUER" \
  2>&1 | tail -12

if [ ! -d "$ARCH" ]; then echo "!!! ARCHIVE FAILED — no xcarchive produced"; exit 1; fi
echo "=== ARCHIVE OK ==="

echo "=== [2/2] EXPORT + UPLOAD to TestFlight ==="
xcodebuild -exportArchive \
  -archivePath "$ARCH" \
  -exportOptionsPlist "$ROOT/scripts/AquaTechWeather-ExportOptions.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEYID" -authenticationKeyIssuerID "$ISSUER" \
  2>&1 | tail -15

echo "=== DONE — 'Upload succeeded' above = new build in TestFlight processing ==="
