# SDR Usage Guide: External Hardware Support

Spectral supports real-world RF spectral analysis from an external RTL-SDR
(RTL2832U-based) dongle. There are two paths to the hardware, with different
maturity:

| Path | Status | How it reaches the dongle |
| --- | --- | --- |
| **rtl_tcp** | ✅ Supported | Connects to an `rtl_tcp` server that owns the USB device (a helper app on Android, or the `rtl_tcp` binary on desktop / a Pi). |
| **Integrated (native USB)** | 🧪 Experimental | Direct libusb access to the dongle. Register bring-up and the sample stream are **not yet implemented** — this source currently emits *simulated* data. See [Developing the native USB driver](#developing-the-native-usb-driver). |

For real signals today, use the **rtl_tcp** path.

## Prerequisites

1.  **RTL-SDR dongle:** any standard RTL2832U-based USB dongle.
2.  **An `rtl_tcp` bridge:**
    - **Android:** a USB OTG adapter plus an RTL-SDR driver app that exposes
      `rtl_tcp` (commonly on `127.0.0.1:1234`).
    - **Desktop / Raspberry Pi:** the `rtl_tcp` binary from `rtl-sdr`
      (`rtl_tcp -a 0.0.0.0 -p 1234`).

## Using a real dongle (rtl_tcp)

### 1. Start the bridge
- **Android:** connect the dongle via OTG, open your RTL-SDR driver app, grant
  USB permission, and start its `rtl_tcp`/server mode. Note the host and port
  (usually `127.0.0.1:1234`).
- **Desktop/Pi:** run `rtl_tcp -a <bind-ip> -p 1234`.

### 2. Configure Spectral
- Tap the **Settings** (tune) icon.
- Under **Mode → Signal Source**, choose `SDR (RF Support)`.
- Set **RF Input Type** to `RTL-TCP`.
- Set **RTL-TCP Host** / **Port** to your bridge (e.g. `127.0.0.1` / `1234`).
- Set **Center Frequency (MHz)** (e.g. `100.0` for FM) and **RF Bandwidth (MHz)**
  (e.g. `2.0` — this is the sample rate sent to the dongle).

### 3. Calibration & gain
- **PPM Correction:** dongle oscillators drift. If a known station appears
  off-center, set **PPM Correction** — Spectral sends it to the device as the
  `rtl_tcp` frequency-correction command on connect.
- **Gain:** on connect Spectral enables the dongle's **automatic gain** (tuner
  AGC + RTL2832 AGC) so it works out of the box. The on-screen **Gain** dial is
  a *display* gain (it scales the visualization), not the hardware gain stage.

### 4. Start capture
- Tap the **Capture** (play) button. Live RF spectrum streams from the dongle.

### Troubleshooting
- **No data / connection refused:** verify the bridge is running and the
  host/port match. On Android, confirm the driver app still holds the USB
  device and its server is started.
- **Frequency offset:** adjust **PPM Correction**.
- **Stuttering:** high bandwidths (> 2.4 MHz) are taxing on mobile. Reduce
  **RF Bandwidth** to `1.0`–`2.0` MHz.

## Developing the native USB driver

The `Integrated RTL-SDR` source is a **work in progress**. The native delegate
(`lib/src/rf/native_sdr_driver_ffi.dart`) currently opens the USB device and
initializes libusb, but the RTL2832U register bring-up and the bulk-transfer
sample stream are not implemented, so `IntegratedRfCaptureService` emits a
*simulated* multi-tone signal. Selecting it will show a **Driver Ready** status
and simulated data — not live RF.

This driver can only be developed and validated **on a physical device with a
real dongle**; it cannot be exercised in CI or on the simulators.

### Hardware reference
`lib/src/rf/rtl2832u.dart` (no FFI) is the reference for an implementation:
- Known dongle USB IDs (`RtlUsbIds`).
- RTL2832U register blocks/registers (`RtlBlock`, `RtlReg`).
- Tuner types and the R82xx I2C address (`RtlTuner`, `kR82xxI2cAddress`).
- The bulk endpoint and crystal constants (`kBulkEndpoint`, `kRtlCrystalHz`).
- The documented 7-step bring-up order (`kBringUpSequence`).

### Implementation outline
Inside `NativeSdrDriverDelegate.initialize()` (after the device is open), a real
implementation performs, over `libusb_control_transfer`:
1. Claim interface 0; reset the demodulator and initialize the baseband.
2. Enable the I2C repeater and probe/identify the tuner (R820T/R828D/E4000/…).
3. Run the tuner init sequence and program the PLL for the LO frequency.
4. Program the resampler from the 28.8 MHz crystal for the sample rate.
5. Apply gains (or enable tuner AGC) and the PPM correction (already plumbed
   through `setGain`/`setPpm`).
6. Submit bulk transfers on endpoint `0x81` and feed the unsigned-8-bit I/Q
   into the same conversion the rtl_tcp path uses (`rtlIqBytesToDouble`).

`librtlsdr` (`src/librtlsdr.c`, `src/tuner_r82xx.c`) is the canonical reference
for the exact register sequences.

### How to test it on-device
1. Build a debug Android build on a device with USB-OTG and a dongle attached:
   `flutter run -d <device>`.
2. In Settings choose **RF → Integrated RTL-SDR** and grant USB permission.
3. Watch the device log (`flutter logs` / `adb logcat`) — the delegate logs the
   detected device and which bring-up steps remain.
4. Implement the steps above incrementally, verifying each register
   read/write against `librtlsdr`, until `IntegratedRfCaptureService` can be
   switched from simulated data to the real bulk-transfer stream.
