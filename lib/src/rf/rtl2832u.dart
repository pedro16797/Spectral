/// Reference constants for the RTL2832U demodulator and its tuner, shared
/// between the rtl_tcp path and the integrated (native USB) path.
///
/// This module deliberately contains no platform code: the register I/O for
/// the integrated driver lives on the Android side, in
/// `android/app/src/main/kotlin/com/example/spectral/usb/`. Keeping the IDs
/// and sample conversion here means both paths agree on them and both can be
/// unit tested without a device.
///
/// Good references: librtlsdr (`src/librtlsdr.c`, `src/tuner_r82xx.c`).
library;

import 'dart:typed_data';

/// USB vendor/product IDs of RTL2832U-based dongles.
///
/// Keep in sync with `android/app/src/main/res/xml/device_filter.xml` (same
/// list in decimal, driving the USB_DEVICE_ATTACHED filter) and with
/// `RtlUsbIds.KNOWN_DEVICES` in the Kotlin driver.
class RtlUsbIds {
  RtlUsbIds._();

  /// Realtek Semiconductor Corp.
  static const int vendorRealtek = 0x0bda;

  /// (vendorId, productId) pairs known to contain an RTL2832U.
  static const List<(int, int)> knownDevices = [
    (0x0bda, 0x2831), // RTL2831U
    (0x0bda, 0x2832), // RTL2832U
    (0x0bda, 0x2834), // RTL2834
    (0x0bda, 0x2837), // RTL2837
    (0x0bda, 0x2838), // RTL2838 (RTL-SDR Blog v3 and most "RTL-SDR" dongles)
    (0x0ccd, 0x00a9), // Terratec Cinergy T Stick Black
    (0x0ccd, 0x00b3), // Terratec NOXON DAB/DAB+
    (0x1d19, 0x1101), // Dexatek DK DVB-T
    (0x1b80, 0xd3a4), // Twintech UT-40
    (0x1f4d, 0xb803), // GTek T803
  ];

  /// Product IDs used by Realtek-branded dongles.
  static const List<int> knownProductIds = [0x2831, 0x2832, 0x2834, 0x2837, 0x2838];

  /// Returns true if [vendorId]/[productId] looks like a supported dongle.
  static bool isKnownDongle(int vendorId, int productId) =>
      knownDevices.contains((vendorId, productId));
}

/// Tuner chips the RTL2832U is commonly paired with.
///
/// The integrated driver drives the R82xx family (branded "RTL-SDR" dongles)
/// and the FC0013 (common in cheaper generic sticks). The rest are detected so
/// the app can explain *why* a dongle is unsupported rather than failing
/// silently.
enum RtlTuner {
  none,
  e4000,
  fc0012,
  fc0013,
  fc2580,
  r820t,
  r828d;

  /// Whether the integrated driver can drive this tuner.
  bool get isSupported =>
      this == RtlTuner.r820t ||
      this == RtlTuner.r828d ||
      this == RtlTuner.fc0013;

  /// Parses the tuner name reported by the platform channel.
  static RtlTuner parse(String? name) {
    if (name == null) return RtlTuner.none;
    final lower = name.toLowerCase();
    return RtlTuner.values.firstWhere(
      (t) => t.name == lower,
      orElse: () => RtlTuner.none,
    );
  }
}

/// Reference crystal frequency (Hz) used for both the RTL2832U resampler and
/// the tuner PLL on standard dongles.
const int kRtlCrystalHz = 28800000;

/// The IF the RTL2832U is programmed to when paired with an R82xx tuner.
const int kR82xxIfFreqHz = 3570000;

/// Sample-stream bulk endpoint on the RTL2832U.
const int kBulkEndpoint = 0x81;

/// Sample rates the RTL2832U resampler cannot produce. Anything outside
/// (225 kHz, 300 kHz] ∪ (900 kHz, 3.2 MHz] is rejected by the hardware.
bool isSupportedRtlSampleRate(int rateHz) {
  if (rateHz <= 225000 || rateHz > 3200000) return false;
  if (rateHz > 300000 && rateHz <= 900000) return false;
  return true;
}

/// Clamps [rateHz] to the nearest rate the RTL2832U resampler supports.
int clampRtlSampleRate(int rateHz) {
  if (rateHz < 225001) return 225001;
  if (rateHz > 3200000) return 3200000;
  if (rateHz > 300000 && rateHz <= 900000) {
    // Snap to whichever end of the dead band is closer.
    return (rateHz - 300000) < (900001 - rateHz) ? 300000 : 900001;
  }
  return rateHz;
}

/// Converts a run of unsigned 8-bit I/Q bytes ([0, 255], centered at 127.5)
/// into normalized doubles in [-1.0, 1.0). [length] bytes are read from [data]
/// starting at [offset].
///
/// Shared by the rtl_tcp and integrated paths — both receive the RTL2832U's
/// native sample format.
Float64List rtlIqBytesToDouble(Uint8List data, int offset, int length) {
  final out = Float64List(length);
  for (int i = 0; i < length; i++) {
    out[i] = (data[offset + i] - 127.5) / 127.5;
  }
  return out;
}
