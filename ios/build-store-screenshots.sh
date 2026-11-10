#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "${RECETARIO_STORE_DEVICE:-}" in iphone|iphone-medium|ipad) ;; *) echo 'Choose iphone, iphone-medium or ipad'; exit 1;; esac
export RECETARIO_SDK_MAJOR=$(xcrun --sdk iphonesimulator --show-sdk-version | cut -d. -f1)
xcrun simctl list devices available --json > /tmp/recetario-store-devices.json
DEVICE_ID=$(python3 - <<'PY'
import json, os
family=os.environ['RECETARIO_STORE_DEVICE']
data=json.load(open('/tmp/recetario-store-devices.json'))
choices=[d for runtime, devices in data['devices'].items() if 'iOS-'+os.environ['RECETARIO_SDK_MAJOR']+'-' in runtime for d in devices]
def valid(d):
    if family=='iphone': return 'iPhone' in d['name'] and 'Pro Max' in d['name']
    if family=='iphone-medium': return 'iPhone' in d['name'] and d['name'].endswith(' Pro')
    return 'iPad' in d['name'] and ('13-inch' in d['name'] or '12.9-inch' in d['name'])
selected=next(d for d in choices if valid(d))
print(selected['udid'])
PY
)
mkdir -p build
node -e 'const fs=require("fs"),crypto=require("crypto");const h=crypto.createHash("sha256").update(fs.readFileSync("Resources/OfflineApp/bundle-manifest.json")).digest("hex"),cfg=JSON.parse(fs.readFileSync("testflight.json"));if(h!==cfg.commonBundleManifestSHA256)throw Error("Unexpected release bundle");'
python3 - <<'PY'
import json, os, pathlib
locale=os.environ.get('RECETARIO_STORE_LOCALE','en')
if locale not in ['all','en','es','ca','de','fr','it','pt']: raise ValueError('Unsupported capture locale')
pathlib.Path('StoreScreenshotTests/StoreLocale.json').write_text(json.dumps({'locale':locale}))
PY
xcodegen generate
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b > build/store-boot.log 2>&1 &
BOOT_PID=$!
xcodebuild -project Recetario.xcodeproj -scheme RecetarioStoreScreenshots -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing
if ! wait "$BOOT_PID"; then
  tail -n 15 build/store-boot.log
  xcrun simctl shutdown "$DEVICE_ID" || true
  xcrun simctl boot "$DEVICE_ID"
  xcrun simctl bootstatus "$DEVICE_ID" -b
fi
xcrun simctl status_bar "$DEVICE_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
python3 store-capture-watch.py watch "$DEVICE_ID" "$RECETARIO_STORE_DEVICE" build/store-captures > build/store-watcher.log 2>&1 &
WATCH_PID=$!
trap 'kill "$WATCH_PID" 2>/dev/null || true' EXIT
set +e
xcodebuild -project Recetario.xcodeproj -scheme RecetarioStoreScreenshots -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$DEVICE_ID" -parallel-testing-enabled NO -derivedDataPath build -resultBundlePath build/StoreResults.xcresult CODE_SIGNING_ALLOWED=NO test-without-building
TEST_STATUS=$?
set -e
kill "$WATCH_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true
cat build/store-watcher.log
python3 store-capture-watch.py emit "$DEVICE_ID" "$RECETARIO_STORE_DEVICE" build/store-captures
exit "$TEST_STATUS"
