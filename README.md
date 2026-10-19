# Recetario iOS
UIKit + WKWebView client for Recetario. Version 0.2 (1), iOS 17 or later.

This repository contains the iOS client and manual simulator validation only.
The web service, user recipes, server source, credentials and private source history are not included.

Run `bash ios/build-simulator.sh` on macOS with Xcode and XcodeGen.
CI uses a standard macOS runner in this public repository. No Actions caches or artifacts are uploaded.
The workflow compiles and runs unit tests. It does not sign an IPA, upload to TestFlight or enable purchases.

The hosted application requires sign-in and an authorized account. Native navigation cooperates with the web interface; it is not an offline app.
All rights reserved, Krazel Studio.
