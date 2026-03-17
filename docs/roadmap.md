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
- [x] **Responsive Layout:** Optimize visualization stacking and sizing for different screen aspects.
- [x] **Custom UI Components:** Implement slick, tailor-made controls for Gain, Sensitivity, and Theme toggling.
- [x] **Modern Visual Language:** Update the interface with subtle gradients, shadows, and smooth transitions.
- [x] **Streamlined Navigation:** Refine the settings access and mode switching for a frictionless experience.
- [x] **Polished Painters:** Improve the visual fidelity of Waveform, FFT, and Waterfall renderings with anti-aliasing and color blending.

## Phase 4: Future Upgrades
- [ ] **RF Support:** Integration with SDR (Software Defined Radio) for RF spectrum visualization.
- [ ] **Advanced Tools:** Markers, peak detection, harmonic analysis.
- [ ] **Expanded Themes:** More color palettes and customizable UI elements.
- [ ] **iOS Port:** Ensuring compatibility and optimizing for the iOS ecosystem.
- [ ] **Global Localization:** Adding support for more languages (Spanish, Portuguese, Japanese, etc.).
