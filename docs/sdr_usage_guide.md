# SDR Usage Guide: External Hardware Support

Spectral now supports real-world RF spectral analysis using external SDR (Software Defined Radio) hardware. This guide explains how to connect and configure your device for SDR support.

## Prerequisites

1.  **RTL-SDR Dongle:** Any standard RTL2832U-based USB dongle.
2.  **USB OTG Adapter:** A "USB On-The-Go" adapter to connect the USB-A dongle to your mobile device's USB-C or Micro-USB port.
3.  **rtl_tcp Driver App (Android):** To bridge the USB hardware to Spectral, you must run a driver that provides an `rtl_tcp` server.
    - **Recommended:** [SDR Driver](https://play.google.com/store/apps/details?id=marto.rtl_tcp_andro) (by Martin Marinov) or similar apps that implement the `rtl_tcp` protocol.

## Connection & Setup

### 1. Hardware Connection
- Connect your antenna to the RTL-SDR dongle.
- Connect the dongle to your phone/tablet using the USB OTG adapter.
- Your device may prompt for permission to access the USB device; grant it.

### 2. Start the rtl_tcp Server
- Open the **SDR Driver** app on your device.
- Ensure the port is set to `1234` (default) and the address is `127.0.0.1` (local loopback).
- Tap **Start Service** or **Start Server**. The driver is now listening for a connection from Spectral.

### 3. Configure Spectral
- Open **Spectral**.
- Tap the **Settings** (tune) icon in the header.
- Under **Mode**, set **Signal Source** to `SDR (RF Support)`.
- Set **RF Input Type** to `RTL-SDR (via rtl_tcp)`.
- Ensure **RTL-TCP Host** is `127.0.0.1` and **Port** is `1234`.
- Adjust **Center Frequency (MHz)** (e.g., `100.0` for FM radio) and **RF Bandwidth (MHz)** (e.g., `2.0`).
- Close Settings.

### 4. Start Capture
- Tap the **Capture** (play) button.
- You should now see live RF spectrum data being streamed from your RTL-SDR hardware!

## Remote SDR Support
Since Spectral uses the `rtl_tcp` network protocol, you can also connect to an SDR dongle plugged into a different device (like a Raspberry Pi or PC) on your local network.
- Simply change the **RTL-TCP Host** in Spectral's settings to the IP address of the remote device.

## Troubleshooting
- **No Data:** Ensure the driver app is actually running and says "Listening...".
- **Permission Denied:** Check your device's USB OTG settings. Some devices require you to manually enable OTG in System Settings.
- **Stuttering:** High bandwidths (above 2.4 MHz) can be taxing for some mobile processors. Try reducing the **RF Bandwidth** to `1.0` or `2.0` MHz.
