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

/// Reassembles RTL2832U byte chunks into whole normalized I/Q pairs.
///
/// TCP segments and USB transfers can split mid-sample; emitting an
/// odd-length chunk as-is would swap I and Q for the rest of the stream. This
/// carries the odd trailing byte into the next chunk instead, so pairs never
/// drift. Shared by the rtl_tcp and integrated capture paths.
class RtlIqChunker {
  int? _pendingByte;

  /// Forget any carried byte. Call when a new stream starts.
  void reset() => _pendingByte = null;

  /// Converts [chunk] (from [offset] on), prepending any byte carried from
  /// the previous call. Returns null when no whole pair is available yet.
  Float64List? process(Uint8List chunk, {int offset = 0}) {
    final int length = chunk.length - offset;
    if (length <= 0) return null;

    final int? pending = _pendingByte;
    final int total = length + (pending == null ? 0 : 1);
    final int usable = total - (total % 2);
    _pendingByte = total.isOdd ? chunk[chunk.length - 1] : null;
    if (usable == 0) return null;

    final out = Float64List(usable);
    int written = 0;
    if (pending != null) {
      out[written++] = (pending - 127.5) / 127.5;
    }
    for (int i = offset; written < usable; i++) {
      out[written++] = (chunk[i] - 127.5) / 127.5;
    }
    return out;
  }
}
