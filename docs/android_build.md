# Android Build Optimization

This document outlines the strategies used to optimize the Android APK size for Spectral and records historical build sizes.

## 📊 Current Build Sizes (as of March 2024)

By splitting the APK per ABI and applying code shrinking, we have significantly reduced the size of the app delivered to users.

| ABI | Size | Description |
|---|---|---|
| **armeabi-v7a** | 11.7 MB | 32-bit ARM (Older devices) |
| **arm64-v8a** | ~8 MB | 64-bit ARM (Modern devices) |
| **x86_64** | ~8 MB | 64-bit x86 (Emulators/Laptops) |
| **Fat APK** | ~24 MB | Combined APK (All ABIs) |

## 🛠️ Optimization Strategies Applied

### 1. Code Shrinking & Resource Stripping
We have enabled R8 in `android/app/build.gradle.kts`:
- `isMinifyEnabled = true`: Removes unused code from the app and its dependencies.
- `isShrinkResources = true`: Removes unused resources.

### 2. ABI Splitting
Using the `--split-per-abi` flag, we generate separate APKs for different CPU architectures. This ensures users only download the code relevant to their device.

### 3. Obfuscation & Symbol Stripping
Using `--obfuscate` and `--split-debug-info`:
- Reduces the size of Dart code by shortening identifier names.
- Removes debug symbols from the APK, moving them to a separate `debug-info` directory for crash analysis.

### 4. Icon Tree Shaking
Flutter automatically removes unused icons from the Material Icons font, reducing its size by ~99%.

## 🚀 How to Build

To generate optimized builds, use the provided script:

```bash
./scripts/build_android.sh
```

## 📦 QA Delivery Recommendation

Given that even optimized APKs are >10MB, we **do not** recommend committing them to the Git repository to avoid long-term bloat.

Instead, we recommend:
1. **GitHub Actions:** Set up a CI workflow that builds the APK on every PR or push to `main`.
2. **Artifact Upload:** Use `actions/upload-artifact` to make the built APKs available for download directly from the GitHub Actions run summary.
3. **Internal Distribution:** For persistent access, consider uploading to a service like Firebase App Distribution or a private S3 bucket.
