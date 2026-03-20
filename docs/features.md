# Spectral Features

This document provides in-depth explanations of the key features and interactions available in Spectral.

## 🎛 Edge Dials (Gain & Sensitivity)

Spectral uses a unique, space-saving interaction model for signal adjustments.

![Edge Dial Interaction](../resources/screenshots/gain_dial.png)

- **Interaction:** Tap the **GAIN** or **SENS** triggers in the interaction bar to make the large edge dials persistent. Alternatively, **long-press and drag** the triggers vertically to adjust values on the fly.
- **Gain:** Adjusts the input signal amplification. Higher gain makes weak signals more visible in the waveform but may cause clipping.
- **Sensitivity:** Adjusts the scaling of the FFT (frequency) data. Higher sensitivity makes spectral peaks more prominent in the bar chart and waterfall.
- **Tactile Feedback:** The dials provide haptic ticks every 0.1 increment to ensure precise control without needing to look at the numbers.

## 🔍 Radio Dial Frequency Focus Slider

The Frequency Focus Slider is a powerful tool for zooming into specific spectral bands.

![Frequency Focus Slider](../resources/screenshots/demo_capturing.png)

- **Panning:** Drag the center of the highlighted window to pan across the entire frequency range.
- **Resizing:** Drag the handles on either side of the window to expand or contract the focus area.
- **Zooming:** The FFT bar chart and Waterfall visualization dynamically update to show only the selected frequency range.
- **Tone Analysis:** When a clear tone is detected, the slider displays the fundamental frequency (e.g., `440Hz` or `12.4kHz`), the corresponding musical note (e.g., `A4`), and any detected harmonics.

## 📊 Advanced Spectral Analysis

Sprint 4.2 introduced professional-grade tools for deep signal analysis.

### Peak Hold
- **Function:** Retains the maximum magnitude of every frequency bin over time.
- **Visual:** Displayed as a thin, persistent line above the real-time FFT bars.
- **Use Case:** Capturing transient signals or observing the peak envelope of a varying signal.

### FFT Averaging
- **Modes:**
  - **Linear:** A moving average of the last *N* frames. Great for steady-state noise reduction.
  - **Exponential:** Weighting recent frames more heavily than older ones. Provides smoother transitions than linear averaging.
- **Control:** The number of averaging frames can be adjusted from 2 to 50 in Settings.

### SNR Estimation
- **Metric:** Real-time Signal-to-Noise Ratio (dB) calculation for the primary peak.
- **Display:** Shown as a HUD overlay in the corner of the FFT chart.
- **Utility:** Helps assess the quality of the incoming signal relative to the background noise floor.

### Interactive Markers
- **Interaction:** Tap anywhere on the FFT bar chart to place up to 3 frequency markers.
- **Display:** Vertical markers with exact frequency labels.
- **Delta Measurement:** Used for measuring precise center frequencies and identifying spectral components.

### Harmonic Overlays
- **Function:** Automatically identifies and highlights integer multiples of a detected fundamental frequency.
- **Visual:** Dashed vertical lines labeled `2H`, `3H`, etc.
- **Use Case:** Identifying harmonic distortion or musical overtone structures.

## 🌊 Waterfall Focus Mode (Slick HUD)

Waterfall Focus Mode transforms the UI into an immersive, data-first dashboard.

![Waterfall Focus Mode](../resources/screenshots/waterfall_focus.png)

- **Activation:** Tap the "Layers" icon in the header to toggle Focus Mode.
- **Layout:** All secondary UI elements (Waveform, FFT Chart, Interaction Bar) are hidden. The Waterfall visualization moves from the background to the foreground with 100% opacity.
- **HUD Elements:** Only the essential Frequency Focus Slider remains visible in its own independent glass card.
- **Aesthetic:** The view includes a subtle scanline overlay and high-contrast gradients to evoke a professional "Heads-Up Display" feel.

## ⚙️ Technical Settings

Fine-tune the spectral engine to match your hardware and signal type.

![Technical Settings](../resources/screenshots/settings_view.png)

- **FFT Window Size:** Choose between 512, 1024, 2048, or 4096 samples.
- **FFT Window Type:** Hanning, Hamming, Blackman, or Bartlett.
- **Themes:** Frost, Magma, Gray, Emerald, or Rainbow.

## 📡 SDR (RF Support)

Spectral supports real-world RF spectral analysis using external SDR (Software Defined Radio) hardware.

- **External Hardware:** Connect standard RTL-SDR dongles via USB OTG.
- **PPM Correction:** Calibrate for hardware oscillator offsets to ensure frequency accuracy.
- **RF Gain Mapping:** Optimize signal strength for varying RF environments.
- **Complex FFT Engine:** Specifically designed for RF I/Q signals with centered DC components.

For setup and hardware requirements, see the [SDR Usage Guide](sdr_usage_guide.md).
