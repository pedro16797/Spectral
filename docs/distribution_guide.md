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
  This script updates the `version` field in `pubspec.yaml` and should be run before any build or distribution (CI release builds run it automatically).

> **Every Play upload needs a higher build number.** The `+N` part becomes
> Android's `versionCode`, and the Play Console rejects an `.aab` whose
> `versionCode` it has already seen — including rejected or discarded
> uploads. Bump `+N` in `VERSION` before merging anything meant for the
> store.

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

Android release builds produced by `scripts/build.sh` are size-optimized:
R8 code/resource shrinking, per-ABI APK splits, and Dart obfuscation with
`--split-debug-info` — the emitted symbols are the same `debug-info` bundle
that Play crash-report deobfuscation consumes (uploaded in step 3 of the
Play checklist below).

---

## 3. Continuous Integration (two paths)

CI is split so nothing debug-signed can ever come out of the release path:

- **`pr-checks.yml`** — every pull request: tests, analysis, a debug APK
  artifact for QA sideloads, and a web build. Needs no secrets, so fork PRs
  work.
- **`release-build.yml`** — every push to `main`: syncs the version from
  `VERSION`, then builds the release-signed **App Bundle** (what the Play
  Store takes) and per-ABI APKs, the release web bundle, an unsigned iOS
  build, and the deobfuscation symbols for Play crash reports. The Android
  job **fails** if the signing secrets below are missing.

### One-time signing setup

1. Generate an upload keystore (keep it and its passwords somewhere safe —
   losing it means losing the ability to update the app unless Play App
   Signing holds the app key):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias upload
   ```
2. Add four repository secrets (**Settings → Secrets and variables →
   Actions**):
   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
   | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` (or your alias) |
   | `ANDROID_KEY_PASSWORD` | key password |
3. For local release builds, create `android/key.properties` (gitignored;
   format documented in `android/app/build.gradle.kts`). Without it, local
   release builds fall back to the **debug key** so `flutter run --release`
   works — never distribute those.

## 4. Publishing to Google Play Store (Android)

> The application ID is `gal.lendas.spectral` — it becomes permanent with
> the first published or installed build. Enroll in **Play App Signing** at
> app creation: Google then holds the app signing key and your keystore is
> only the upload key, which Play can reset if lost.

### Prerequisites
- A Google Play Developer Account.
- The signing setup above (CI produces the signed `.aab` on every push to `main`).

### App content requirements (Play Console blocks release on these)

These are filled in the Play Console under **App content** and the store
listing; none of them come from the build:

- **Privacy policy URL** — required for every app. Host one under
  lendas.gal; the honest content for Spectral is short: audio is captured
  only on user action, processed on-device, and never transmitted or
  stored; the app sends no data anywhere (the only network use is the
  user-configured rtl_tcp connection to their own server).
- **Permission declarations** — the microphone (`RECORD_AUDIO`) usage must
  match the listing description; "real-time audio spectrum visualization"
  is the declared purpose. No sensitive-permission form is needed (mic is
  not in Play's restricted list), but reviewers do check consistency.
- **Data safety form** — declare "no data collected, no data shared"
  (accurate as long as the above holds; revisit if analytics or crash
  reporting are ever added).
- **Content rating questionnaire (IARC)** — utility app, no user content;
  rates "Everyone".
- **App access** — declare that all functionality is available without
  credentials (there is no login).
- **Ads declaration** — no ads.
- **Target audience** — 18+ or 13+ is simplest; selecting children's age
  groups triggers the much stricter Families policy for no benefit here.

### Store graphic assets

- **Hi-res icon, 512×512 PNG:** downscale `resources/icon.png` (1024×1024).
- **Feature graphic, 1024×500 PNG/JPG:** required for the listing; nothing
  in the repo produces this — design one once (app name + a waterfall
  shot works) and keep it with the store assets.
- **Screenshots:** minimum 2 per form factor; `package_distribution.sh`
  produces compliant phone (1242×2208) and tablet (2048×2732 / 2732×2048)
  sets.

### Testing-track gate for new developer accounts

**Personal** developer accounts created after Nov 2023 must run a closed
test with **at least 12 testers opted in for 14 continuous days** before
Google unlocks production access. **Organization** accounts are exempt. If
publishing under a personal account, start the closed track (the CI `.aab`
works for it) well before the intended launch date. Recommended order
regardless: internal testing → closed testing → production.

### Uploading Artifacts
1. Go to the [Google Play Console](https://play.google.com/console/).
2. Select your app and go to **Production** > **Create new release**.
3. Upload the App Bundle: `android-appbundle-release` artifact from the
   latest `main` CI run (or `distribution/v<VERSION>/android/*.aab` from
   `package_distribution.sh`). Also upload the `android-debug-symbols`
   artifact under **App bundle explorer → Downloads → native debug symbols**
   so crash reports deobfuscate.
4. In the **Graphics** section, upload screenshots from `distribution/v<VERSION>/android/phone/` and `tablet/`.

> **Hands-off upload (optional next step):** once a Play service account
> exists, a final workflow job can push the `.aab` to the internal track
> automatically on every `main` push (e.g. the `r0adkll/upload-google-play`
> action with a `PLAY_SERVICE_ACCOUNT_JSON` secret). Left out until the Play
> app and service account are created.

### Store Listing
- Copy content from `docs/app_store_listing.md`.
- Set the category to **Tools** or **Productivity**.

---

## 5. Publishing to Apple App Store (iOS)

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

## 6. Web Distribution

Spectral can also be hosted as a static web application.

1. Extract `distribution/v<VERSION>/web/spectral-web.zip`.
2. Upload the contents to any static hosting provider (e.g., GitHub Pages, Netlify, or your own server).
3. Ensure the web server supports the required mime-types for Flutter (especially `.wasm` if applicable).
