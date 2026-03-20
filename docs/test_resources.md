# Audio Test Resources

This document provides a list of high-quality, open-source or freely available audio samples and resources for testing the spectral analysis and visualization capabilities of Spectral.

## High-Quality Technical Samples

### EBU SQAM (Sound Quality Assessment Material)
The European Broadcasting Union (EBU) provides standardized material for subjective and objective audio testing.
- **Link:** [SQAM - MIT Media Lab](https://sound.media.mit.edu/resources/mpeg4/audio/sqam/)
- **Description:** Includes individual instruments (Glockenspiel, Trumpet, Harpsichord), speech (English, French), and complex tunes.
- **Usage:** Ideal for verifying harmonic detection, tone mapping, and FFT clarity.

### Freesound.org
A massive database of creative-commons licensed audio.
- **Link:** [Freesound.org](https://freesound.org/)
- **Search Terms:** "sine sweep", "white noise", "pink noise", "audio test tone", "uncompressed pcm".
- **Usage:** Good for testing wide-band visualizations and waterfall responsiveness.

### Internet Archive (Audio Archive)
- **Link:** [Archive.org - Audio](https://archive.org/details/audio)
- **Description:** Includes historic recordings, open-source music, and technical archives.

## Synthetic Test Signals
For automated or programmatic testing, it is often better to generate signals. Use the `_startDemoData` method in `lib/main.dart` as a reference for:
- **Sine Waves:** Pure frequencies for precision testing.
- **Noise Floors:** Verifying SNR calculations.
- **Sweeps:** Testing dynamic range and frequency response across the spectrum.

## SDR/RF Sample Repositories
For RF mode testing without hardware:
- **Signal Identification Guide Wiki:** [SigIDWiki](https://www.sigidwiki.com/) often includes baseband (I/Q) recordings of various radio signals.
- **RTL-SDR.com Samples:** Various community-contributed I/Q files.
