# Recetario iPhone · 0.3.1 (3)

UIKit + locally bundled interface, SQLite on device, recipes and photos offline.
Menus, cooking timers, pantry, shopping, preferences and complete JSON backups
work without a user account. AI uses App Attest and a protected server endpoint;
API keys and server credentials are never part of this repository.

The owner explicitly requested a public client repository and standard public
macOS CI on 4 November 2026. The Site, server source and user recipe data remain
private. No production data or runtime secrets are included here.

Run `bash ios/build-simulator.sh` with Xcode and XcodeGen. The manual simulator
workflow compiles and runs XCTest without signing, uploading or purchases.
The owner authorized internal TestFlight and the common corrections on 9 November 2026.
Version 0.3.1 (3) is VALID and IN_BETA_TESTING in the existing internal group,
verified through App Store Connect after successful CI run 42550342540.
Binary source: 4fff9bc6444838ba3c93188a9b9222894f44f767. Shared bundle manifest:
6910548d1623b08f3433762b93537582b23737f9b99d61a9f76dc4f349604cef.
WebView correction flows pass at 320, 390 and 430 px in CI42550339713;
this includes the full-screen sharing guide, forms, guarded drafts and URL/caption delivery.
Physical iPhone checks, including positive App Attest, remain pending.
External testing and App Review have not been started.

All rights reserved, Krazel Studio.
