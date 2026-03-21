# Roadmap & Sprint Plan

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Phase 4: Active Development

### Current Sprint 4.3: Mobile Expansion & Regional Localization
- [ ] **Mobile Parity:** Achieving full feature parity and performance optimization on iOS.
- [ ] **Tablet Optimization:** Dedicated large-screen layouts with multi-pane visualization for iPads and Android tablets.
- [ ] **Regional Localization:** Adding support for Spanish, Galician, Portuguese, Catalonian, and Basque.

---

## Future Sprints & Upgrades
- **Professional Analysis Tools:** Data recording, playback, and export (CSV/IQ).
- **SIGINT Module:** Automated protocol identification for common digital signals (DMR, AIS, ADS-B).
- **Cloud Signal Sharing:** Securely sync and share captured spectrum snapshots and IQ recordings.
- **AR Spectral Overlay:** Visualizing signal strength and direction using the camera and ARCore/ARKit.
- **Remote SDR Clusters:** Support for connecting to multiple distributed `rtl_tcp` nodes simultaneously.
- **On-Device Machine Learning:** Real-time signal classification and automatic anomaly detection.
- **Global Expansion:** Adding support for more languages (Japanese, German, etc.).

---

## Completed Milestones

### Phases
- **Phase 1: Foundation:** Project bootstrapping, core documentation, and cross-platform Flutter environment setup.
- **Phase 2: MVP Features:** Functional real-time audio visualization with waveform, FFT, and waterfall displays.
- **Phase 3: UI Modernization:** Liquid Glass aesthetic implementation with interactive edge dials and HUD focus mode.

### Sprints
- **Sprint 4.1: RF Foundation:** Established signal abstraction layer and integrated SDR support via libusb and rtl_tcp.
- **Sprint 4.2: Advanced Spectral Analysis:** Implemented Peak Hold, FFT Averaging, SNR estimation, Spectral Markers, Harmonic Overlays, and AM/FM Demodulation with Audio Output.
