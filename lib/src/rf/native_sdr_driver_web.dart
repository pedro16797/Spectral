import 'dart:async';
import 'package:flutter/foundation.dart';
import 'native_sdr_driver.dart';

class NativeSdrDriverDelegate implements NativeSdrDriverInterface {
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<bool> initialize() async {
    _isInitialized = true;
    return true;
  }

  @override
  Future<void> setGain(int gainIndex) async {
    debugPrint("NativeSdrDriverWeb: Setting gain index $gainIndex (mocked)");
  }

  @override
  Future<void> setPpm(int ppm) async {
    debugPrint("NativeSdrDriverWeb: Setting PPM correction $ppm (mocked)");
  }

  @override
  void dispose() {
    _isInitialized = false;
  }
}
