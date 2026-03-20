import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:libusb_android/libusb_android.dart';
import 'package:libusb_android_helper/libusb_android_helper.dart';

class NativeSdrDriver {
  static final NativeSdrDriver _instance = NativeSdrDriver._internal();
  factory NativeSdrDriver() => _instance;
  NativeSdrDriver._internal();

  LibusbAndroidBindings? _bindings;
  Pointer<libusb_context>? _context;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (!Platform.isAndroid) return false;

      final DynamicLibrary lib = DynamicLibrary.open('libusb_android.so');
      _bindings = LibusbAndroidBindings(lib);

      // libusb_android has the restriction on Android that no USB devices can be found.
      // We must list them via libusb_android_helper to get the native file descriptor.
      final devices = await LibusbAndroidHelper.listDevices();
      if (devices == null || devices.isEmpty) {
        debugPrint("No USB devices found.");
        return false;
      }

      // In a real app, we'd iterate and check properties.
      // libusb_android_helper 1.0.1 UsbDevice only has 'identifier' (path).
      // We'll try to open the first available device for this prototype.
      UsbDevice? targetDevice = devices.first;

      // Request permission
      final hasPermission = await targetDevice.requestPermission();
      if (!hasPermission) {
        debugPrint("USB permission denied.");
        return false;
      }

      // Open the device to get the native file descriptor
      final success = await targetDevice.open();
      if (!success) {
        debugPrint("Failed to open USB device.");
        return false;
      }

      // Initialize libusb context
      final ctxPtr = calloc<Pointer<libusb_context>>();
      final res = _bindings!.libusb_init(ctxPtr);
      if (res != 0) {
        debugPrint("Libusb initialization failed: $res");
        return false;
      }
      _context = ctxPtr.value;

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint("NativeSdrDriver initialization error: $e");
      return false;
    }
  }

  void dispose() {
    if (_context != null && _bindings != null) {
      _bindings!.libusb_exit(_context!);
    }
    _isInitialized = false;
  }
}
