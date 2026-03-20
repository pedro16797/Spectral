# Roadmap & Sprint Plan

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Phase 4: Active Development

### Current Sprint 4.2: Advanced Spectral Analysis & SDR Enhancements
Building on the RF foundation to provide professional-grade signal analysis tools.

#### Task 1: Peak Analysis & Signal Stability
- [ ] **Subtask 1.1: Peak Hold:** Implement a visual persistence mode for spectral peaks.
- [ ] **Subtask 1.2: FFT Averaging:** Add selectable averaging modes (Linear, Exponential) for noise reduction.
- [ ] **Subtask 1.3: SNR Estimation:** Real-time signal-to-noise ratio calculation for the primary peak.

#### Task 2: Interactive Analysis Tools
- [ ] **Subtask 2.1: Spectral Markers:** Allow users to place movable markers on the FFT chart to measure delta-frequency/power.
- [ ] **Subtask 2.2: Harmonic Overlays:** Visual indicators for integer multiples of a selected fundamental frequency.

#### Task 3: Advanced RF Controls
- [ ] **Subtask 3.1: RF Gain Mapping:** Map raw libusb gain stages to a user-friendly slider/dial.
- [ ] **Subtask 3.2: Frequency Correction (PPM):** Add a calibration setting for SDR hardware oscillator offsets.

---

## Future Sprints & Upgrades
- **Sprint 4.3: Professional Analysis Tools:** Implementation of recording and playback for captured data, data logging for long-term signal monitoring, and export features (CSV/IQ).
- **Expanded Themes:** New high-contrast palettes and user-definable visual presets.
- **Cross-Platform Parity:** Optimizing for iOS ecosystem and tablets/desktop.
- **Global Localization:** Adding support for more languages (Spanish, Portuguese, Japanese, etc.).

---

## Completed Milestones

### Phases
- **Phase 1: Foundation:** Project bootstrapping, core documentation, and cross-platform Flutter environment setup.
- **Phase 2: MVP Features:** Functional real-time audio visualization with waveform, FFT, and waterfall displays.
- **Phase 3: UI Modernization:** Liquid Glass aesthetic implementation with interactive edge dials and HUD focus mode.

### Sprints
- **Sprint 4.1: RF Foundation:** Established signal abstraction layer and integrated SDR support via libusb and rtl_tcp.
