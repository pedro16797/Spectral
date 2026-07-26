# SDR Usage Guide: External Hardware Support

Spectral supports real-world RF spectral analysis from an external RTL-SDR
(RTL2832U-based) dongle. There are two paths to the hardware, with different
maturity:

| Path | Status | How it reaches the dongle |
| --- | --- | --- |
| **Integrated (native USB)** | 🧪 Android only, unvalidated | The app claims the dongle itself over USB host (OTG) and runs the RTL2832U + R82xx bring-up in-process. No bridge app needed. See [The integrated USB driver](#the-integrated-usb-driver). |
| **rtl_tcp** | ✅ Supported | Connects to an `rtl_tcp` server that owns the USB device (a helper app on Android, or the `rtl_tcp` binary on desktop / a Pi). |

The integrated path is the one that "just works" from a plugged-in dongle, but
its register-level driver has **not yet been validated against real hardware**.
If it misbehaves, the **rtl_tcp** path is the proven fallback.

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

## Using a real dongle (integrated USB)

This is the path that responds to simply plugging the dongle in.

### 1. Plug it in
Connect the dongle through a USB-OTG adapter. Android matches it against
`android/app/src/main/res/xml/device_filter.xml` and offers to open Spectral:

> Open Spectral to handle this USB device?

Accepting that dialog also grants Spectral USB permission for the dongle, so
there is no second prompt. If you tick *"Use by default for this USB device"*,
future plug-ins go straight into the app.

Spectral also listens for attach/detach while it is already running, so a
dongle plugged in mid-session is picked up without restarting.

### 2. Confirm the driver came up
- If the app was already on another source, a prompt appears: **"RTL-SDR dongle
  detected"** → tap **USE IT** to switch to the integrated source.
- Otherwise open **Settings → Mode → RF Input Type → `Integrated RTL-SDR`**.
  The panel underneath reports the driver state, and offers **Connect** when
  there is something to act on (permission needed, or a dongle waiting to be
  opened).

States you may see:

| Panel | Meaning |
| --- | --- |
| **Dongle Ready** | Open and tuned. The tuner chip is shown next to it. |
| **Dongle Detected** | Attached and permitted, not yet opened — tap **Connect**. |
| **USB Permission Needed** | Attached, but access not granted — tap **Connect**. |
| **No Dongle Detected** | Nothing attached (or the OTG adapter is not passing it through). |
| **USB Not Available** | Platform has no USB host path (web/desktop) — use rtl_tcp. |
| **Driver Error** | Bring-up failed; the reason is shown (e.g. unsupported tuner). |

### 3. Tune and capture
Set **Center Frequency** and **RF Bandwidth**, then hit **Capture**. Gain runs
on the dongle's automatic gain control by default.

**RF Bandwidth is capped by the hardware.** The RTL2832U resampler tops out at
3.2 MS/s, so a larger figure is clamped rather than accepted — an unclamped
setting would stretch the frequency axis over a span the dongle never captured,
which reads on screen as one featureless smear instead of separate stations.
To watch a wider slice of spectrum, move the centre frequency instead.

### 4. Tuning a station
The spectrum and waterfall always show the **whole captured RF band**, even
while demodulating — it is the map you tune by.

1. Find a peak in the waterfall.
2. Drag the frequency slider so the selected window sits over it.
3. With **Demodulation Mode** set to `FM` (or `AM`) and **Audio Output** on,
   you hear *only that window*.

The selection is a digital down-converter, not just a zoom: the chosen slice is
mixed to baseband and decimated before demodulation, so neighbouring stations
are filtered out rather than mixed in. Retuning is instant and does not restart
the stream — the dongle stays parked on the centre frequency while you move
around inside the band it is already receiving.

Very narrow selections are widened to 48 kHz, the least that can still carry
audio. FM broadcast wants roughly 150-200 kHz to sound clean; a much narrower
window will be audible but muffled.

### Supported hardware
The driver implements two tuner families:

| Tuner | Typically found in |
| --- | --- |
| **R820T / R820T2 / R828D** | Branded "RTL-SDR" dongles (RTL-SDR Blog v3 etc.) |
| **FC0013** | Cheaper generic RTL2832U / DVB-T sticks |

E4000, FC0012 and FC2580 are *detected and reported* rather than half-driven —
use rtl_tcp for those. Note that FC0012 and FC0013 share I2C address `0xc6`
and differ only in the ID byte (`0xa1` vs `0xa3`), so a dongle reporting
`0xa1` is deliberately rejected rather than driven with the FC0013 sequence.

Recognised USB IDs live in three places that must stay in sync:
- `android/app/src/main/res/xml/device_filter.xml` (decimal; drives the attach dialog)
- `android/app/src/main/kotlin/com/example/spectral/usb/RtlUsbIds.kt`
- `lib/src/rf/rtl2832u.dart` (`RtlUsbIds.knownDevices`)

### Troubleshooting
- **Nothing happens when you plug the dongle in:** the VID/PID is probably not
  in `device_filter.xml`. Find it with `adb shell dumpsys usb` (or `lsusb` on a
  host) and add it to all three lists above.
- **The attach dialog never reappears:** you previously chose "use by default"
  for another app. Clear that app's defaults in Android settings.
- **"Driver Error":** the panel names the stage that failed. The common ones:
  - *No tuner responded on the demodulator's I2C bus* — the message includes
    what each candidate address returned (e.g. `R820T@0x34=0x00 exp 0x69`). The
    demodulator answered but the tuner did not, which points at the I2C
    repeater or control-transfer addressing in `Rtl2832u.kt` rather than at
    your hardware.
  - *The RTL2832U demodulator is not responding* — no register reads are
    getting through at all. Suspect the OTG cable or a flaky dongle first.
  - *PLL did not lock during filter calibration* — the tuner was found, so the
    problem is in `R82xxTuner.setPll()` / the calibration sequence.
  - *Unsupported tuner* — an E4000/FC001x dongle. Use rtl_tcp.
  - *Could not claim the USB interface* / *Android refused to open the dongle*
    — this is the only genuine "another app has it" case. Note that an
    **uninstalled** app cannot hold the device: Android USB access is
    userspace-only, so removing the package removes its claim and its
    attach association. Look for an app that is still installed.
- **Opens, then no data:** check the sample rate is one the resampler supports
  (see `isSupportedRtlSampleRate`) and watch for `bulk read failed` in logcat.

## The integrated USB driver

The register-level driver lives on the Android side, in
`android/app/src/main/kotlin/com/example/spectral/usb/`, so it can use
`UsbDeviceConnection` directly — no libusb, no FFI:

| File | Responsibility |
| --- | --- |
| `SpectralUsbBridge.kt` | Platform channels, USB permission, attach/detach broadcasts, the bulk-read thread. |
| `Rtl2832u.kt` | Demodulator register I/O, baseband bring-up, I2C repeater, resampler, IF/PPM. |
| `R82xxTuner.kt` | R820T/R828D init, filter calibration, PLL programming, gain. |
| `Fc0013Tuner.kt` | FC0013 init, band/VHF-track selection, PLL + VCO calibration, LNA gain. |
| `RtlTunerDriver.kt` | The interface both tuners implement. |
| `RtlUsbIds.kt` | Recognised VID/PIDs. |

The Dart half (`lib/src/rf/native_sdr_driver_channel.dart`) mirrors the driver
state, exposes hot-plug events, and forwards the sample stream;
`IntegratedRfCaptureService` converts the unsigned-8-bit I/Q with the same
`rtlIqBytesToDouble` the rtl_tcp path uses.

All blocking USB work runs on a dedicated I/O thread — the R82xx bring-up alone
sleeps ~250 ms, which would otherwise stall the platform thread.

### ⚠️ Validation status

All sequences are transcribed from `librtlsdr` (`src/librtlsdr.c`,
`src/tuner_r82xx.c`, `src/tuner_fc0013.c`). CI has no USB hardware, so nothing
here is covered by automated tests — what follows is what has and has not been
observed on a real device.

**Confirmed working on hardware** (an FC0013 dongle, Android):
- USB attach, permission, `claimInterface`
- Vendor control transfers in both directions
- `Rtl2832u.initBaseband()` — the full RTL2832U register bring-up
- Demodulator register read-back
- The I2C repeater, and an I2C read returning a correct tuner ID

That covers the whole RTL2832U layer. The tuner drivers sit on top of it.

**Not yet validated:**
- `Fc0013Tuner` — PLL/VCO calibration and gain, written against a dongle that
  is available for testing.
- `R82xxTuner` — *entirely unexercised*, and cannot be validated with an FC0013
  dongle. If it misbehaves, suspect in this order: `freqRanges`
  band-switching constants, then `INIT_ARRAY` / `setTvStandard()` filter
  calibration, then the `setPll()` arithmetic.
- `Rtl2832u.setSampleRate()` / `setIfFreq()` arithmetic beyond the defaults.

When a bring-up fails, the settings panel names the stage rather than a generic
error, and `Rtl2832u.selfTest()` (exposed over the channel as `selfTest`) reads
back key registers — so a failure is diagnosable without `adb`, which matters
when the phone's only USB port is occupied by the dongle.

### How to test it on-device
1. Build a debug Android build on a device with USB-OTG and a dongle attached:
   `flutter run -d <device>`.
2. Plug the dongle in and accept the system dialog.
3. Watch `adb logcat -s Rtl2832u:* R82xxTuner:* SpectralUsbBridge:*` — every
   failed control transfer is logged with its block and register address.
4. Compare any failing step against `librtlsdr`, which is the canonical
   reference for the exact register sequences.
