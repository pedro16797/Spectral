# Agent Guidance for Spectral

This document is the entry point for AI agents working on Spectral. It covers what is agent-specific; the general contributor process lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## Project Overview
Spectral is a mobile-first Flutter application (Android priority, iOS-compatible) for observing spectral and wave data (audio, RF via RTL-SDR) in a modern, elegant, and performant way.

## Current Status
The core feature set is implemented — real-time visualization, SDR capture (native USB and rtl_tcp), demodulation, 11 languages, and a distribution pipeline. See [docs/roadmap.md](docs/roadmap.md) for what is in flight (currently: hardware validation of the native SDR driver) and [docs/project_structure.md](docs/project_structure.md) for the architecture.

## Core Directives
- **Performance First:** Spectral data processing and rendering must be highly optimized; keep per-frame work off the widget-rebuild path.
- **Cross-Platform Readiness:** Android is the first target, but avoid platform lock-in; web and iOS builds must keep working (note the conditional imports around `dart:io`).
- **Localization:** All user-facing strings are externalized to `resources/locales/*.json`. When adding a string, add the key to **all** locale files — key parity with `en.json` is expected.
- **Minimize Blast Radius:** Touch only the files and functions required for your task.
- **Validate:** Run `flutter analyze` and `flutter test` before finalizing.
- **Versioning:** Sync the version from the root `VERSION` file using `scripts/sync_version.sh` before any distribution.
- **Screenshots:** If a change has visual impact, update the project's screenshots (see "Visual Documentation" in CONTRIBUTING.md).

## Documentation Maintenance
Keep the project documentation accurate as you work:
- **`docs/project_structure.md`**: update when directories or major files are added or moved.
- **`docs/roadmap.md`**: update as features are implemented or reprioritized.
- **`README.md`** / **`AGENTS.md`**: update on high-level status or guideline changes.
