# Recetario iPhone · 0.3 (1)

UIKit + locally bundled interface, SQLite on device, recipes and photos offline.
Menus, cooking timers, pantry, shopping, preferences and complete JSON backups
work without a user account. AI uses App Attest and a protected server endpoint;
API keys and server credentials are never part of this repository.

The owner explicitly requested a public client repository and standard public
macOS CI on 4 November 2026. The Site, server source and user recipe data remain
private. No production data or runtime secrets are included here.

Run `bash ios/build-simulator.sh` with Xcode and XcodeGen. The manual simulator
workflow compiles and runs XCTest without signing, uploading or purchases.
TestFlight and App Review remain blocked until runtime/device checks are done.

All rights reserved, Krazel Studio.
