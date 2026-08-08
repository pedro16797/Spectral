# Roadmap & Sprint Plan

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Phase 4: Active Development
- **Native SDR driver hardware validation:** the RTL2832U/R82xx/FC0013 bring-up is transcribed from librtlsdr but has not yet been validated against physical dongles (see `Rtl2832u.selfTest` and the notes in `docs/sdr_usage_guide.md`).
- **Release signing:** generate an upload keystore and provide it via `android/key.properties` before any store publish (see `docs/distribution_guide.md`); the application ID is now `com.jundroo.spectral`.

---

## Future Sprints & Upgrades
- **Professional Analysis Tools:** Data recording, playback, and export (CSV/IQ).
- **SIGINT Module:** Automated protocol identification for common digital signals (DMR, AIS, ADS-B).
- **Remote SDR Clusters:** Support for connecting to multiple distributed `rtl_tcp` nodes simultaneously.
- **Expanded Hardware Support:** Integration with additional SDR front-ends beyond RTL-SDR.
- **Spectrum Archiving:** Efficient storage and indexing of historical signal activity.

---

## Completed Milestones

### Phases
- **Phase 1: Foundation:** Project bootstrapping, core documentation, and cross-platform Flutter environment setup.
- **Phase 2: MVP Features:** Functional real-time audio visualization with waveform, FFT, and waterfall displays.
- **Phase 3: UI Modernization:** Liquid Glass aesthetic implementation with interactive edge dials and HUD focus mode.

### Sprints
- **Sprint 4.1: RF Foundation:** Established signal abstraction layer and integrated SDR support via libusb and rtl_tcp.
- **Sprint 4.2: Advanced Spectral Analysis:** Implemented Peak Hold, FFT Averaging, SNR estimation, Spectral Markers, Harmonic Overlays, and AM/FM Demodulation with Audio Output.
- **Sprint 4.3: Mobile Expansion & Multi-Language Support:** Achieved iOS parity, tablet-optimized multi-pane layouts, and added support for 10 new global and regional languages.
- **Sprint 4.4: Distribution Readiness:** Established automated versioning, custom icon generation, and a complete distribution packaging pipeline for app store readiness.
