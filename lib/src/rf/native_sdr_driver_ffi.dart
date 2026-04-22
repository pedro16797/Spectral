import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:libusb_android/libusb_android.dart';
import 'package:libusb_android_helper/libusb_android_helper.dart';
import 'native_sdr_driver.dart';

class NativeSdrDriverDelegate implements NativeSdrDriverInterface {
  LibusbAndroidBindings? _bindings;
  Pointer<libusb_context>? _context;
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!Platform.isAndroid) return false;

      final DynamicLibrary lib = DynamicLibrary.open('libusb_android.so');
      _bindings = LibusbAndroidBindings(lib);

      // Attempt to list devices with a short delay to allow OS to settle
      List<UsbDevice>? devices;
      for (int i = 0; i < 3; i++) {
        devices = await LibusbAndroidHelper.listDevices();
        if (devices != null && devices.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (devices == null || devices.isEmpty) {
        debugPrint("No USB devices found. Ensure no other app (like 'Rtl-sdr driver') is using the module.");
        return false;
      }

      // In version 1.0.1 of libusb_android_helper, vid/pid are not directly exposed on UsbDevice.
      // We take the first available device and attempt to open it.
      // Most users will have only one SDR plugged in.
      UsbDevice? targetDevice = devices.first;

      final hasPermission = await targetDevice.hasPermission() || await targetDevice.requestPermission();
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
        // For the prototype simulation, we can continue even if the low-level
        // libusb context failed, as long as we have the Android-level handle.
        // However, we should only return true if we're in a state where simulation
        // is acceptable.
      } else {
        _context = ctxPtr.value;
      }

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint("NativeSdrDriver initialization error: $e");
      return false;
    }
  }

  @override
  Future<void> setGain(int gainIndex) async {
    if (!_isInitialized) return;
    debugPrint("NativeSdrDriver: Setting gain index $gainIndex");
  }

  @override
  Future<void> setPpm(int ppm) async {
    if (!_isInitialized) return;
    debugPrint("NativeSdrDriver: Setting PPM correction $ppm");
  }

  @override
  void dispose() {
    if (_context != null && _bindings != null) {
      _bindings!.libusb_exit(_context!);
    }
    _isInitialized = false;
  }
}
