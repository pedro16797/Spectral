# iOS & iPadOS Testing Guide

Since physical iOS devices may not always be available during development, this guide outlines methods for testing the Spectral application on Apple platforms.

## 1. Local iOS Simulator (macOS Only)
If you have access to a machine running macOS, you can use the iOS Simulator included with Xcode.

1.  **Install Xcode** from the Mac App Store.
2.  **Open Simulator:** `open -a Simulator`.
3.  **Run Spectral:** `flutter run` and select the simulator as the target device.

## 2. Automated Testing in CI (GitHub Actions)
Our GitHub Actions workflow (`.github/workflows/multi-platform-build.yml`) utilizes `macos-latest` runners to build the iOS application. While it doesn't currently run functional UI tests on a simulator, you can verify build integrity.

To run tests on a simulator in CI, one can add a job that:
- Starts a simulator.
- Runs `flutter test` or integration tests using `drive`.

## 3. Cloud Testing Services
Cloud providers offer access to real iOS devices and simulators for remote testing.

### Firebase Test Lab (Recommended)
Firebase Test Lab supports iOS "Robo" tests and Game Loops, as well as XCTest-based UI tests.
- **Process:** Upload the `.ipa` or `.zip` of the app bundle.
- **Benefits:** Provides screenshots, videos, and logs from actual Apple hardware.

### BrowserStack / Sauce Labs
These services provide interactive remote access to real iPhones and iPads.
- **Process:** Upload the built app to their platform and interact with it through your browser.
- **Benefits:** Great for manual exploratory testing and verifying UI responsiveness on different screen sizes (e.g., iPad Pro vs. iPhone SE).

## 4. Web-Based "iOS-Like" Testing
While not a perfect substitute for the native environment, the Web build of Spectral can be tested in Safari or using Chrome DevTools' device emulation for iOS devices.

1.  **Build Web:** `flutter build web --release`.
2.  **DevTools Emulation:** Open the app in Chrome, press `F12`, and toggle the device toolbar. Select "iPhone" or "iPad" to test responsive layouts.

## 5. TestFlight (Beta Testing)
For testing on real devices without being in the same location:
1.  Upload a build to **App Store Connect**.
2.  Distribute to internal or external testers via **TestFlight**.
3.  Testers can provide feedback and crash reports directly through the TestFlight app.
