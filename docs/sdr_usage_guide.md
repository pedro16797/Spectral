# SDR Usage Guide: External Hardware Support

Spectral now supports real-world RF spectral analysis using external SDR (Software Defined Radio) hardware. This guide explains how to connect and configure your device for SDR support.

## Prerequisites

1.  **RTL-SDR Dongle:** Any standard RTL2832U-based USB dongle.
2.  **USB OTG Adapter:** A "USB On-The-Go" adapter to connect the USB-A dongle to your mobile device's USB-C or Micro-USB port.

## Connection & Setup

### 1. Hardware Connection
- Connect your antenna to the RTL-SDR dongle.
- Connect the dongle to your phone/tablet using the USB OTG adapter.

### 2. Configure Spectral
- Open **Spectral**.
- Tap the **Settings** (tune) icon in the header.
- Under **Mode**, set **Signal Source** to `SDR (RF Support)`.
- Set **RF Input Type** to `Integrated RTL-SDR`.
- Adjust **Center Frequency (MHz)** (e.g., `100.0` for FM radio) and **RF Bandwidth (MHz)** (e.g., `2.0`).

### 3. Hardware Calibration
SDR hardware oscillators can have small frequency offsets (measured in PPM - Parts Per Million).
- **PPM Correction:** If a known signal (like a local FM station) appears slightly off-center, adjust the **PPM Correction** value in Settings to calibrate your hardware.
- **RF Gain Mapping:** Use the **Gain** dial to adjust the hardware's internal gain stages for optimal signal-to-noise ratio.

### 4. Driver Setup (Android Only)
- The first time you select `Integrated RTL-SDR`, Spectral will request permission to access the USB device.
- Tap **Allow** in the system dialog.
- You will see a **Driver Ready** status in the settings once initialization is complete.

### 5. Start Capture
- Tap the **Capture** (play) button.
- You should now see live RF spectrum data being streamed from your RTL-SDR hardware!

## Remote SDR Support
Since Spectral supports the `rtl_tcp` network protocol, you can also connect to an SDR dongle plugged into a different device (like a Raspberry Pi or PC) on your local network.
- Simply change the **RTL-TCP Host** in Spectral's settings to the IP address of the remote device.

## Troubleshooting
- **No Data:** Ensure the driver is actually initialized and the status says "Ready".
- **Permission Denied:** Check your device's USB OTG settings. Some devices require you to manually enable OTG in System Settings.
- **Frequency Offset:** Use the **PPM Correction** setting to align your center frequency with known signal standards.
- **Stuttering:** High bandwidths (above 2.4 MHz) can be taxing for some mobile processors. Try reducing the **RF Bandwidth** to `1.0` or `2.0` MHz.
