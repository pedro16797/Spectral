# iOS & iPadOS Testing Guide

Physical iOS devices are not always available during development. These are the
ways to test Spectral on Apple platforms, roughly in order of fidelity per
effort.

## 1. Local iOS Simulator (macOS only)
1. **Install Xcode** from the Mac App Store.
2. **Open Simulator:** `open -a Simulator`.
3. **Run Spectral:** `flutter run` and select the simulator as the target device.

## 2. CI build verification (GitHub Actions)
`.github/workflows/release-build.yml` builds an unsigned iOS app bundle on a
`macos-latest` runner on every push to `main` (tests and analysis run on every
PR via `pr-checks.yml`). This verifies build integrity but does not exercise
the UI on a simulator; a future job could boot a simulator and run integration
tests via `flutter drive`.

## 3. Cloud device farms
- **Firebase Test Lab:** upload the `.ipa`/app bundle; runs on real Apple
  hardware and returns screenshots, videos, and logs. Supports XCTest-based UI
  tests.
- **BrowserStack / Sauce Labs:** interactive remote access to real iPhones and
  iPads through the browser — best for manual exploratory testing across
  screen sizes (e.g. iPad Pro vs. iPhone SE).

## 4. Web build with iOS device emulation
Not a substitute for the native environment, but quick for layout checks:
build with `flutter build web --release`, open the app in Chrome, and use
DevTools' device toolbar (`F12`) to emulate iPhone/iPad viewports. Safari on a
Mac gets closer to WebKit behavior.

## 5. TestFlight (beta testing on real devices)
1. Upload a build to **App Store Connect**.
2. Distribute to internal or external testers via **TestFlight**.
3. Testers provide feedback and crash reports through the TestFlight app.
