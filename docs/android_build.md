# Android Build Optimization

This document outlines the strategies used to keep the Android APK small and
records reference build sizes.

## 📊 Reference Build Sizes

Measured in March 2024, before the native SDR driver and the full localization
set were added — treat them as a lower bound and a regression baseline rather
than current figures:

| ABI | Size | Description |
|---|---|---|
| **armeabi-v7a** | 11.7 MB | 32-bit ARM (older devices) |
| **arm64-v8a** | ~8 MB | 64-bit ARM (modern devices) |
| **x86_64** | ~8 MB | 64-bit x86 (emulators/laptops) |
| **Fat APK** | ~24 MB | Combined APK (all ABIs) |

Current sizes can be read off any `release-build.yml` run's artifacts, or
reproduced locally with `bash scripts/build.sh android`.

## 🛠️ Optimization Strategies Applied

### 1. Code Shrinking & Resource Stripping
R8 is enabled in `android/app/build.gradle.kts`:
- `isMinifyEnabled = true`: removes unused code from the app and its dependencies.
- `isShrinkResources = true`: removes unused resources.

### 2. ABI Splitting
The `--split-per-abi` flag generates separate APKs per CPU architecture, so
users only download the code relevant to their device.

### 3. Obfuscation & Symbol Stripping
`--obfuscate` and `--split-debug-info`:
- Shorten Dart identifier names.
- Move debug symbols out of the APK into a separate `debug-info` directory,
  which is what Play crash-report deobfuscation consumes (see the
  distribution guide).

### 4. Icon Tree Shaking
Flutter automatically strips unused icons from the Material Icons font
(~99% reduction).

### 5. Sample Exclusion
The audio/RF test samples under `resources/samples/` are deliberately not
listed in `pubspec.yaml`, so production builds don't ship them (they are
bundled temporarily only for screenshot generation).

## 🚀 How to Build

```bash
bash scripts/build.sh android         # release AAB + per-ABI APKs
bash scripts/build.sh android-debug   # debug APK for QA sideloads
```

## 📦 QA Delivery

Built APKs are **not** committed to the repository. CI provides them instead:

- **Every pull request:** `pr-checks.yml` uploads a debug-signed APK as the
  `android-apk-debug` artifact — download it from the run summary for QA
  sideloads.
- **Every push to `main`:** `release-build.yml` uploads the release-signed
  App Bundle, per-ABI APKs, and debug symbols.

For persistent distribution to testers, a service like Firebase App
Distribution can be layered on top; see `docs/distribution_guide.md` for the
store pipeline.
