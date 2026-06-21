/// Reference constants and the documented bring-up sequence for the RTL2832U
/// demodulator and its tuner, used by the (experimental) native USB driver.
///
/// This module deliberately contains no FFI: it is the hardware reference a
/// real, on-device implementation of [NativeSdrDriverDelegate] builds against.
/// The actual register I/O happens over libusb control transfers
/// (`libusb_control_transfer`) and the sample stream over bulk transfers
/// (`libusb_bulk_transfer`) on endpoint 0x81 — both of which must be validated
/// against a physical dongle, so they are intentionally not implemented blind.
///
/// Good references: librtlsdr (`src/librtlsdr.c`, `src/tuner_r82xx.c`).
library;

/// USB vendor/product IDs of common RTL2832U dongles.
class RtlUsbIds {
  RtlUsbIds._();

  /// Realtek Semiconductor Corp.
  static const int vendorRealtek = 0x0bda;

  /// Product IDs frequently used by RTL-SDR dongles.
  static const List<int> knownProductIds = [
    0x2832, // RTL2832U
    0x2838, // RTL2838 (most "RTL-SDR" blog dongles)
  ];

  /// Returns true if [vendorId]/[productId] looks like a supported dongle.
  static bool isKnownDongle(int vendorId, int productId) =>
      vendorId == vendorRealtek && knownProductIds.contains(productId);
}

/// RTL2832U register blocks, selected via the high byte of a control-transfer
/// index. Reads/writes target `(block << 8) | addr`.
class RtlBlock {
  RtlBlock._();

  static const int demod = 0x00; // Demodulator
  static const int usb = 0x01; // USB controller
  static const int sys = 0x02; // System
  static const int tun = 0x03; // Tuner (I2C repeater pass-through)
  static const int rom = 0x04;
  static const int ir = 0x05;
  static const int iic = 0x06; // I2C
}

/// Key RTL2832U registers (within their [RtlBlock]).
class RtlReg {
  RtlReg._();

  // USB block
  static const int usbSysctl = 0x2000;
  static const int usbEpaCtl = 0x2148;
  static const int usbEpaMaxpkt = 0x2158;

  // SYS block
  static const int demodCtl = 0x3000;
  static const int gpo = 0x3001;
  static const int gpoEn = 0x3003;
  static const int gpd = 0x3004;
  static const int demodCtl1 = 0x300b;
}

/// Tuner chips the RTL2832U is commonly paired with, and their 7-bit I2C
/// addresses on the demodulator's I2C bus.
enum RtlTuner {
  none,
  e4000, // 0x64 (8-bit) -> check 0x02
  fc0012,
  fc0013,
  fc2580,
  r820t, // 8-bit addr 0x34 -> 7-bit 0x1a
  r828d,
}

/// 7-bit I2C address of the R820T/R828D tuner family.
const int kR82xxI2cAddress = 0x1a;

/// The documented bring-up order. A real implementation performs each of these
/// over the corresponding control transfers:
///
/// 1. Open the USB device, claim interface 0.
/// 2. Reset the demodulator: write [RtlReg.usbSysctl] (USB), then initialize
///    the baseband (DEMOD block soft reset, set IF frequency, AGC defaults).
/// 3. Enable the I2C repeater and probe the tuner at [kR82xxI2cAddress]
///    (and the other [RtlTuner] addresses) to identify it.
/// 4. Run the tuner init sequence (for R82xx: ~30 registers, then program the
///    PLL for the requested LO frequency).
/// 5. Set the sample rate by programming the RTL resampler ratio from the
///    28.8 MHz crystal.
/// 6. Set gains (tuner LNA/Mixer/VGA, or enable tuner AGC) and apply the PPM
///    frequency correction.
/// 7. Submit bulk transfers on endpoint 0x81 and convert the unsigned-8-bit
///    interleaved I/Q into samples (see `rtlIqBytesToDouble`).
const List<String> kBringUpSequence = [
  'open+claim',
  'reset-demod',
  'probe-tuner',
  'init-tuner',
  'set-sample-rate',
  'set-gain+ppm',
  'bulk-stream',
];

/// Sample-stream bulk endpoint on the RTL2832U.
const int kBulkEndpoint = 0x81;

/// Reference crystal frequency (Hz) used for both the RTL2832U resampler and
/// the tuner PLL on standard dongles.
const int kRtlCrystalHz = 28800000;
