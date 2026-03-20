# Project Learnings: Sprint 4.2 - Advanced Spectral Analysis

## Technical Insights
- **FFT Averaging:** Implementing linear and exponential averaging significantly reduces spectral noise. Linear averaging requires a sliding window (buffer), while exponential averaging only needs the last state and an alpha factor, making it more memory-efficient.
- **Peak Hold:** Maintaining a separate buffer for the maximum seen magnitude per frequency bin provides a persistence effect that is crucial for detecting intermittent signals.
- **SNR Estimation:** A simple but effective way to estimate SNR is comparing the primary peak magnitude against the average noise floor of the rest of the spectrum.
- **Interactivity in CustomPainters:** To map screen coordinates back to frequency, you must account for non-linear scales (like the `frequencySkew` power-law) in the inverse mapping.
- **Platform Abstraction in Flutter:** Using the Platform Interface pattern with conditional imports is essential for maintaining a single codebase that supports both FFI (native) and Web (mocked/stubbed) targets.

## Repository Procedures
- **Conditional Imports:** Use `if (dart.library.html)` in imports to switch between `io` and `html` based implementations at compile time.
- **Pre-commit Testing:** Always run `flutter test` to ensure core logic remains sound after refactoring.
