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
# macOS Bash3.2 treats an empty array as unset under nounset. Name the complete
# test target explicitly instead of expanding an empty optional argument list.
TEST_FILTER=(-only-testing:RecetarioTests)
case "${RECETARIO_TEST_SCOPE:-all}" in
  all|'') ;;
  webview) TEST_FILTER=(-only-testing:RecetarioTests/OfflineAppTests) ;;
  cooking) TEST_FILTER=(-only-testing:RecetarioTests/LocalizationUITests/testEditorialCookingKeepsControlsAndRecipeAtPhoneAndTabletWidths) ;;
  *) echo 'Unknown test scope'; exit 1 ;;
esac
mkdir -p build
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b > build/simulator-boot.log 2>&1 &
BOOT_PID=$!
# Compile while the clean runner performs its first simulator migration.
xcodebuild -project Recetario.xcodeproj -scheme Recetario -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing
if ! wait "$BOOT_PID"; then
  # A fresh runner can fail its first SpringBoard boot. Retry only this empty
  # test simulator once; no app data or signing environment is involved.
  tail -n 15 build/simulator-boot.log
  xcrun simctl shutdown "$DEVICE_ID" || true
  xcrun simctl boot "$DEVICE_ID"
  xcrun simctl bootstatus "$DEVICE_ID" -b
fi
tail -n 30 build/simulator-boot.log
xcodebuild -project Recetario.xcodeproj -scheme Recetario -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -parallel-testing-enabled NO -derivedDataPath build -resultBundlePath build/TestResults.xcresult CODE_SIGNING_ALLOWED=NO "${TEST_FILTER[@]}" test-without-building
echo 'Unsigned simulator app: build/Build/Products/Debug-iphonesimulator/Recetario.app'
