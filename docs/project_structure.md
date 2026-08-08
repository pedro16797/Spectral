# Project Structure

This document outlines the directory structure and the purpose of each component
in the Spectral repository. Spectral is a Flutter application.

## Architecture at a glance

The real-time signal pipeline is owned by **`SignalController`**
(`lib/src/core/signal_controller.dart`), a `ChangeNotifier` that manages source
lifecycle, demodulation, FFT, and the rolling visualization history. `main.dart`
is a thin **view** that observes the controller:

- **Per-frame repaints** are driven by `controller.frame` (a `FrameTicker`),
  which only repaints the live `CustomPaint` layers (waveform, FFT, waterfall)
  via `AnimatedBuilder` + `RepaintBoundary` — the surrounding glass/blur chrome
  is *not* rebuilt every frame.
- **Discrete state** (e.g. capture on/off) is delivered through the controller's
  `ChangeNotifier` listeners.
- Signal sources are created by an injectable `SignalSourceFactory`, which keeps
  source selection in one place and makes the pipeline unit-testable with a fake
  source.

## Directory Overview

- **`lib/main.dart`**: App entry point and the top-level view (`SpectralApp`,
  `SpectralHomePage`).
- **`lib/src/`**: Application source code.
    - **`core/`**: Pipeline and shared domain logic.
        - `signal_controller.dart`: Owns the real-time pipeline (see above).
        - `signal_source.dart`: `SignalSource` interface implemented by every
          capture backend.
        - `fft_service.dart`: FFT, windowing, peak-hold, averaging, tone/SNR
          detection.
        - `channel_extractor.dart`: digital down-converter. Mixes the tuned
          slice of a wideband I/Q stream to baseband with an NCO and decimates
          to the channel rate, so demodulation hears one station rather than the
          whole captured band. `planChannel()` works out the offset and
          decimation for a requested window.
        - `settings_model.dart`: `AppSettings` immutable model + validated
          serialization, including `SpectrumView` (whether the analysis chain
          describes the RF band or the demodulated audio).
        - `audio_filters.dart`: DC blocker, FM de-emphasis, and the streaming
          linear resampler used to condition the audio-output path.
        - `spectral_theme.dart`: Per-theme accent/background colors, shared
          surface colors, and the waterfall magnitude→color ramp.
    - **`audio/`**: `audio_capture_service.dart` (mic capture via `record`) and
      `audio_output_service.dart` (PCM playback via `mp_audio_stream`).
    - **`rf/`**: RF acquisition backends.
        - `rtl_tcp_capture_service.dart`: `rtl_tcp` client (uses `dart:io`); has
          a web stub (`rtl_tcp_capture_service_stub.dart`) selected via
          conditional import so the web build does not pull in `dart:io`.
        - `simulated_rf_capture_service.dart`: simulated RF source (mock).
        - `integrated_rf_capture_service.dart`: live I/Q from a USB dongle
          claimed by the app itself, via the native driver below.
        - `rtl2832u.dart`: platform-free RTL constants shared by both RF paths
          (known USB IDs, tuner enum, sample-rate limits, I/Q conversion).
        - `native_sdr_driver.dart` + `native_sdr_driver_channel.dart` /
          `native_sdr_driver_web.dart`: platform driver delegate (Android USB
          host via platform channels, unsupported on web). The register-level
          driver itself lives in
          `android/app/src/main/kotlin/com/example/spectral/usb/`.
    - **`ui/`**: Rendering and interaction.
        - `waveform_painter.dart`, `fft_bar_chart_painter.dart`,
          `waterfall_painter.dart`: `CustomPainter` visualizations.
        - `radio_dial_focus_slider.dart`: frequency zoom/pan control.
        - `edge_dial.dart`: the small dial-trigger chips and the large
          edge-mounted dial they expand into.
        - `settings_view.dart`: settings dialog and inline tablet panel.
    - **`services/`**: `settings_service.dart` (persistence via
      `shared_preferences`).
    - **`utils/`**: Shared helpers — `audio_utils.dart` (PCM/decimation),
      `frequency_formatter.dart`, `frequency_scale.dart` (skew transforms),
      `spectrum_bins.dart` (maps display columns onto FFT bins for both
      painters; handles the RF case where the spectrum is centred on the tuned
      frequency rather than starting at 0 Hz), `localization_helper.dart`,
      `mock_file_signal_source.dart`.
- **`test/`**: Unit and widget tests.
- **`docs/`**: Project documentation, roadmaps, and guides.
- **`resources/`**: Static assets.
    - **`locales/`**: JSON files for internationalization.
    - **`screenshots/`**: Marketing/store screenshots.
- **`scripts/`**: Tooling — `build.sh <android|web|ios>` (release builds),
  `package_distribution.sh`, `sync_version.sh`, `generate_screenshots.py`,
  `generate_samples.py`, `generate_placeholder_icon.py`.
- **`.github/workflows/`**: CI — `pr-checks.yml` (tests, analysis, debug
  builds on pull requests) and `release-build.yml` (release-signed App
  Bundle/APKs, web, and unsigned iOS builds on pushes to `main`), both via
  `scripts/build.sh`.
- **`android/` `ios/` `web/` `linux/` `macos/` `windows/`**: Flutter platform
  runners. The register-level USB driver lives in
  `android/app/src/main/kotlin/com/example/spectral/usb/`.

## Root Files

- **`AGENTS.md`**: Guidance for AI agents working on the project.
- **`CONTRIBUTING.md`**: Guidelines for contributing to the project.
- **`README.md`**: General project overview and setup instructions.
- **`VERSION`**: Single source of truth for the app version (synced into
  `pubspec.yaml` via `scripts/sync_version.sh`).
- **`LICENSE`**: The project's MIT license terms.
