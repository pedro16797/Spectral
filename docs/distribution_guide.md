# Spectral Distribution & Publishing Guide

This guide details the process for versioning, bundling, and publishing Spectral to the Google Play Store and Apple App Store.

## 1. Versioning System

Spectral uses a single source of truth for versioning.

- **File:** `VERSION` (located at the root)
- **Format:** `Major.Minor.Patch+BuildNumber` (e.g., `1.1.0+2`)
- **Synchronization:**
  ```bash
  ./scripts/sync_version.sh
  ```
  This script updates the `version` field in `pubspec.yaml` and should be run before any build or distribution.

## 2. Automated Distribution Bundle

To generate a complete set of distribution artifacts (APKs, Web Zip, and Screenshots), use the master packaging script:

```bash
./scripts/package_distribution.sh
```

### What this script does:
1. Synchronizes the version in `pubspec.yaml`.
2. Runs optimized production builds for **Android** (splitting APKs by ABI).
3. Runs a production build for the **Web** and creates a zip archive.
4. Generates **Screenshots** in multiple resolutions using Playwright:
   - **Phone (5.5"):** For standard App Store/Play Store listings.
   - **Modern Phone (6.7"):** For iPhone Max and large Android devices.
   - **Tablet Landscape (12.9"):** For iPad Pro and Android tablets.
5. Organizes all files into a structured `distribution/v<VERSION>/` directory.

---

## 3. Publishing to Google Play Store (Android)

### Prerequisites
- A Google Play Developer Account.
- A signed release build (configured in `android/app/build.gradle.kts`).

### Uploading Artifacts
1. Go to the [Google Play Console](https://play.google.com/console/).
2. Select your app and go to **Production** > **Create new release**.
3. Upload the APKs from `distribution/v<VERSION>/android/*.apk`.
   *Note: Using Google Play App Signing is recommended.*
4. In the **Graphics** section, upload screenshots from `distribution/v<VERSION>/android/phone/` and `tablet/`.

### Store Listing
- Copy content from `docs/app_store_listing.md`.
- Set the category to **Tools** or **Productivity**.

---

## 4. Publishing to Apple App Store (iOS)

### Prerequisites
- An Apple Developer Program membership.
- A Mac for code signing and final `.ipa` generation.

### Finalizing the iOS Build
1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select **Product > Archive**.
3. Once the archive is complete, click **Distribute App** and follow the prompts to upload it to App Store Connect.

### Store Listing
1. Go to [App Store Connect](https://appstoreconnect.apple.com/).
2. Select your app version.
3. Upload screenshots from `distribution/v<VERSION>/ios/phone/` and `tablet/`.
4. Copy descriptions and metadata from `docs/app_store_listing.md`.

---

## 5. Web Distribution

Spectral can also be hosted as a static web application.

1. Extract `distribution/v<VERSION>/web/spectral-web.zip`.
2. Upload the contents to any static hosting provider (e.g., GitHub Pages, Netlify, or your own server).
3. Ensure the web server supports the required mime-types for Flutter (especially `.wasm` if applicable).
