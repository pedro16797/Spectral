import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:libusb_android/libusb_android.dart';
import 'package:libusb_android_helper/libusb_android_helper.dart';
import 'native_sdr_driver.dart';
import 'rtl2832u.dart';

/// EXPERIMENTAL native RTL-SDR driver.
///
/// This currently opens the USB device and initializes libusb, but the
/// RTL2832U register bring-up and the bulk-transfer sample stream (see
/// [kBringUpSequence] in `rtl2832u.dart`) are not yet implemented — those
/// require validation against physical hardware. Until then the integrated RF
/// source emits simulated data. For real hardware today, use the rtl_tcp
/// source with a bridge (an Android driver app or the desktop `rtl_tcp`).
class NativeSdrDriverDelegate implements NativeSdrDriverInterface {
  LibusbAndroidBindings? _bindings;
  Pointer<libusb_context>? _context;
  bool _isInitialized = false;

  // Requested tuner state, applied once register I/O is implemented.
  int _gainIndex = 0;
  int _ppm = 0;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!Platform.isAndroid) return false;

      final DynamicLibrary lib = DynamicLibrary.open('libusb_android.so');
      _bindings = LibusbAndroidBindings(lib);

      final devices = await LibusbAndroidHelper.listDevices();
      if (devices == null || devices.isEmpty) {
        debugPrint("No USB devices found.");
        return false;
      }

      UsbDevice? targetDevice = devices.first;

      final hasPermission = await targetDevice.requestPermission();
      if (!hasPermission) {
        debugPrint("USB permission denied.");
        return false;
      }

      final success = await targetDevice.open();
      if (!success) {
        debugPrint("Failed to open USB device.");
        return false;
      }

      final ctxPtr = calloc<Pointer<libusb_context>>();
      final res = _bindings!.libusb_init(ctxPtr);
      if (res != 0) {
        debugPrint("Libusb initialization failed: $res");
        return false;
      }
      _context = ctxPtr.value;

      // A full implementation would now run the RTL2832U bring-up sequence
      // (see rtl2832u.dart) over control transfers, then stream samples over
      // bulk endpoint kBulkEndpoint. That path needs hardware validation and
      // is not yet implemented.
      debugPrint("NativeSdrDriver: USB device opened; expecting a Realtek "
          "(0x${RtlUsbIds.vendorRealtek.toRadixString(16)}) RTL2832U dongle. "
          "Register bring-up (${kBringUpSequence.length} steps) is not yet "
          "implemented; the integrated source emits simulated data.");

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint("NativeSdrDriver initialization error: $e");
      return false;
    }
  }

  @override
  Future<void> setGain(int gainIndex) async {
    _gainIndex = gainIndex;
    if (!_isInitialized) return;
    debugPrint("NativeSdrDriver: tuner gain index -> $_gainIndex (pending hardware support)");
  }

  @override
  Future<void> setPpm(int ppm) async {
    _ppm = ppm;
    if (!_isInitialized) return;
    debugPrint("NativeSdrDriver: PPM correction -> $_ppm ppm (pending hardware support)");
  }

  @override
  void dispose() {
    if (_context != null && _bindings != null) {
      _bindings!.libusb_exit(_context!);
    }
    _isInitialized = false;
  }
}
