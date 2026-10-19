#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodebuild >/dev/null || { echo 'Requires macOS and Xcode'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen from its official release or Homebrew'; exit 1; }
xcodegen generate
xcrun simctl list devices available --json > /tmp/recetario-simulators.json
DEVICE_ID=$(python3 -c 'import json; d=json.load(open("/tmp/recetario-simulators.json")); print(next(x["udid"] for devices in d["devices"].values() for x in devices if "iPhone" in x["name"]))')
xcodebuild -project Recetario.xcodeproj -scheme Recetario -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO test
echo 'Unsigned simulator app: build/Build/Products/Debug-iphonesimulator/Recetario.app'
