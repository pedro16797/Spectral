import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class NativeSdrDriverInterface {
  bool get isInitialized;
  Future<bool> initialize();
  Future<void> setGain(int gainIndex);
  Future<void> setPpm(int ppm);
  void dispose();
}

class NativeSdrDriver implements NativeSdrDriverInterface {
  static final NativeSdrDriver _instance = NativeSdrDriver._internal();
  factory NativeSdrDriver() => _instance;
  NativeSdrDriver._internal();

  NativeSdrDriverInterface? _delegate;

  void setDelegate(NativeSdrDriverInterface delegate) {
    _delegate = delegate;
  }

  @override
  bool get isInitialized => _delegate?.isInitialized ?? false;

  @override
  Future<bool> initialize() async {
    return await _delegate?.initialize() ?? false;
  }

  @override
  Future<void> setGain(int gainIndex) async {
    await _delegate?.setGain(gainIndex);
  }

  @override
  Future<void> setPpm(int ppm) async {
    await _delegate?.setPpm(ppm);
  }

  @override
  void dispose() {
    _delegate?.dispose();
  }
}
