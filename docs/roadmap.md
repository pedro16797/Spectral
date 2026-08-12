# Roadmap

This document outlines the strategic plan for Spectral, from MVP to future iterations.

## Phase 4: Active Development

- **Native SDR driver hardware validation** — *importance: high* (gates
  promoting the integrated driver from experimental), *complexity: medium*
  (needs physical dongles; R82xx hardware in particular). The bring-up is
  transcribed from librtlsdr. The RTL2832U layer has been confirmed on real
  hardware, but the tuner drivers have not — FC0013 PLL/gain is untested and
  R82xx is entirely unexercised (see the validation-status section of
  `docs/sdr_usage_guide.md`).
- **Release signing** — *importance: high* (blocks any store publish),
  *complexity: low*. Generate an upload keystore and provide it via
  `android/key.properties` (see `docs/distribution_guide.md`). The
  application ID is `gal.lendas.spectral`.

---

## Future Features

Ranked by importance to the product and estimated implementation complexity.

| Feature | Importance | Complexity | Notes |
| --- | --- | --- | --- |
| **Data recording, playback & export (CSV / raw I/Q)** | High | Medium | The natural next analysis tool; replaying saved captures also removes the need for live hardware when developing and testing. |
| **Expanded hardware support (SDR front-ends beyond RTL-SDR)** | Medium | High | Each front-end (Airspy, HackRF, SDRplay, …) needs its own native driver or bridge protocol. |

### Descoped

Considered and dropped as out of scope for a mobile spectral-visualization app:

- **Automated protocol identification (DMR, AIS, ADS-B):** per-protocol
  decoders are a different product domain from spectrum visualization.
- **Remote SDR clusters (multiple simultaneous `rtl_tcp` nodes):** multi-node
  aggregation is infrastructure tooling; a single remote `rtl_tcp` source is
  already supported.
- **Spectrum archiving with indexing:** the useful kernel — saving and
  replaying captures — is covered by recording & export above.

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
