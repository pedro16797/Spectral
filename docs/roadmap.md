# Roadmap & Sprint Plan

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Phase 1: Project Setup & Foundation
- [x] Initialize project structure.
- [x] Create core documentation (README, CONTRIBUTING, AGENTS).
- [x] Define directory layout.
- [x] Set up localization base.
- [x] Define initial tech stack and bootstrap mobile project (Flutter).

## Phase 2: MVP Features (Current)
The goal of the MVP is to provide a functional and performant audio spectral visualizer.

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

## Phase 3: UI Modernization & UX Streamlining
- [x] **Liquid Glass Aesthetic:** Implemented a minimalist, high-end UI using frosted glass containers (`BackdropFilter`), radial gradients, and organic glows.
- [x] **Frequency Focus (Zoom):** Added ability to focus and zoom into specific spectral bands (0–22,050Hz) with dynamic frequency labeling.
- [x] **Refined Interactions:** Standardized circular controls and minimalist interaction bars for GAIN and SENS.
- [x] **Modernized Typography & Layout:** Shifted to a de-emphasized branding approach with clean, high-contrast layouts.
- [x] **Optimized Visualizations:** Enhanced Waveform, FFT, and Waterfall painters with anti-aliasing, soft gradients, and sub-pixel clarity.

## Phase 4: Future Upgrades
- [ ] **RF Support:** Integration with SDR (Software Defined Radio) for RF spectrum visualization.
- [ ] **Advanced Tools:** Markers, peak detection, harmonic analysis.
- [ ] **Expanded Themes:** More color palettes and customizable UI elements.
- [ ] **iOS Port:** Ensuring compatibility and optimizing for the iOS ecosystem.
- [ ] **Global Localization:** Adding support for more languages (Spanish, Portuguese, Japanese, etc.).
