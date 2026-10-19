#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodebuild >/dev/null || { echo 'Requires macOS and Xcode'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen from its official release or Homebrew'; exit 1; }
xcodegen generate
xcodebuild -version
export RECETARIO_SDK_MAJOR=$(xcrun --sdk iphonesimulator --show-sdk-version | cut -d. -f1)
xcrun simctl list devices available --json > /tmp/recetario-simulators.json
DEVICE_ID=$(python3 -c 'import json,os; d=json.load(open("/tmp/recetario-simulators.json")); print(next(x["udid"] for runtime,devices in d["devices"].items() if "iOS-"+os.environ["RECETARIO_SDK_MAJOR"]+"-" in runtime for x in devices if "iPhone" in x["name"]))')
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcodebuild -project Recetario.xcodeproj -scheme Recetario -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -parallel-testing-enabled NO -derivedDataPath build -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO test
echo 'Unsigned simulator app: build/Build/Products/Debug-iphonesimulator/Recetario.app'
