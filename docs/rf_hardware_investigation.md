# RF Hardware Investigation Findings

This document summarizes the investigation into raw RF access on standard mobile devices, as part of Sprint 4.1.

## Internal Antenna Access (Subtask 3.1)
- **Status:** Restricted / Inaccessible.
- **Findings:**
    - Standard Android and iOS APIs do not provide raw access to the internal RF front-end for security and regulatory reasons.
    - Cellular and Wi-Fi modems operate in a "black box" fashion, exposing only high-level connectivity metrics (RSSI, SNR) rather than raw I/Q samples.
    - Even with root/jailbreak access, the hardware is typically not designed to pipe raw wideband RF data to the application processor.

## Headphone-Wire FM Support (Subtask 3.3)
- **Status:** Hardware-Dependent / Proprietary.
- **Findings:**
    - Many Android devices have FM radio chips that use the headphone wire as an antenna.
    - However, access to these chips is typically restricted to the manufacturer's own FM app.
    - There is no standard Android API for raw FM signal capture. While some chips (like those from Qualcomm or Broadcom) can be accessed via low-level kernel interfaces or proprietary HALs (e.g., `com.caf.fmradio`), these are not portable and rarely expose raw I/Q data (usually only decoded audio).
    - Modern flagship devices are increasingly omitting the FM radio chip and 3.5mm jack entirely.

## Conclusion & Path Forward
For the purposes of Spectral, "Internal RF" is not a viable source for raw spectral analysis on mainstream consumer hardware.

The primary path for real-world RF support is **External Hardware via USB OTG**.
- Using standard RTL-SDR dongles.
- Communicating via the `rtl_tcp` protocol or direct USB vendor-specific drivers (using `android.hardware.usb`).
- This approach provides portable, high-quality, wideband I/Q data that Spectral can process using its complex FFT engine.
