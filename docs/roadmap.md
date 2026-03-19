# Roadmap & Sprint Plan

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Current Sprint 4.1: RF Foundation & Signal Abstraction
The focus of this sprint is to transition Spectral from a pure audio visualizer to a multi-source spectral analysis tool.

### Task 1: Signal Architecture Refactoring
- [x] **Subtask 1.1: SignalProvider Interface:** Create a generic abstraction for interleaved data streams.
- [x] **Subtask 1.2: Audio Service Migration:** Adapt existing microphone capture to the new interface.
- [x] **Subtask 1.3: Complex FFT Engine:** Support I/Q magnitude calculation and FFT shifting.

### Task 2: RF Infrastructure & Mocking
- [x] **Subtask 2.1: Mock RF Service:** Implement a simulated I/Q generator with noise and signal peaks.
- [x] **Subtask 2.2: Extended Settings:** Add Center Frequency and Bandwidth controls.

### Task 3: Device & Hardware Investigation
- [x] **Subtask 3.1: Internal Antenna Access:** Investigate Android/iOS APIs for raw RF access (likely restricted). [See Findings](rf_hardware_investigation.md)
- [ ] **Subtask 3.2: External SDR Bindings:** Prototype USB OTG communication for RTL-SDR hardware.
- [x] **Subtask 3.3: Headphone Antenna Support:** Explore FM chip integration via system APIs for headphone-wire antennas. [See Findings](rf_hardware_investigation.md)

## Phase 1: Project Setup & Foundation
- [x] Initialize project structure.
- [x] Create core documentation (README, CONTRIBUTING, AGENTS).
- [x] Define directory layout.
- [x] Set up localization base.
- [x] Define initial tech stack and bootstrap mobile project (Flutter).

## Phase 2: MVP Features (Complete)
The goal of the MVP was to provide a functional and performant audio spectral visualizer.

### Core Visualizations
- [x] **Real-time Waveform:** High-performance rendering of time-domain audio data.
- [x] **FFT Bar Chart:** Frequency-domain visualization with configurable bins.
- [x] **Waterfall Display:** Rolling spectrogram to visualize frequency over time.

### Configuration & UI
- [x] **Theme Support:** Initial implementation of Light and Dark modes.
- [x] **Range Control:** Ability to set frequency and amplitude ranges.
- [x] **Modern Interface:** Clean, responsive design for Android devices.

### Technical Foundation
- [x] **Audio Engine:** Low-latency audio capture and processing.
- [x] **Signal Processing:** Efficient FFT implementation and windowing.
- [x] **Localization:** Full support for English, ready for other languages.

## Phase 3: UI Modernization & UX Streamlining (Complete)
- [x] **Liquid Glass Aesthetic:** Frosted glass containers, radial gradients, and organic glows.
- [x] **Frequency Focus (Zoom):** 0–22,050Hz bands with dynamic frequency labeling.
- [x] **Refined Interactions:** Standardized circular controls and minimalist interaction bars.
- [x] **Modernized Typography & Layout:** De-emphasized branding with clean layouts.
- [x] **Optimized Visualizations:** Enhanced painters with anti-aliasing and soft gradients.
- [x] **Waveform Ghosting:** Temporal history with fading effects.
- [x] **Slick HUD Refinement:** Waterfall background layer with scanline overlays.
- [x] **Interactive Edge Dials:** Large semi-circular dials for Gain and Sensitivity.

## Phase 4: Future Upgrades
- [ ] **RF Support:** Integration with SDR (Software Defined Radio) and advanced spectrum analysis.
- [ ] **Advanced Tools:** Markers, peak detection, harmonic analysis.
- [ ] **Expanded Themes:** More color palettes and customizable UI elements.
- [ ] **iOS Port:** Ensuring compatibility and optimizing for the iOS ecosystem.
- [ ] **Global Localization:** Adding support for more languages (Spanish, Portuguese, Japanese, etc.).
