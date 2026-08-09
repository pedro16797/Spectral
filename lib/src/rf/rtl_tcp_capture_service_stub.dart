import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';

/// Web stub for [RtlTcpCaptureService].
///
/// Raw TCP sockets (`dart:io`) are not available on the web platform, so the
/// real `rtl_tcp` client cannot be compiled there. This stub provides an
/// API-compatible implementation that reports the source as unavailable,
/// allowing the app to build for web without pulling in `dart:io`.
class RtlTcpCaptureService implements SignalSource {
  final String host;
  final int port;
  final int _requestedSampleRate;

  final _dataController = StreamController<Float64List>.broadcast();

  RtlTcpCaptureService({
    this.host = '127.0.0.1',
    this.port = 1234,
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppmCorrection = 0,
    int? tunerGainTenthsDb,
  }) : _requestedSampleRate = sampleRate;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => _requestedSampleRate;

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async {
    debugPrint("RtlTcpCaptureService: rtl_tcp is not supported on web.");
    return false;
  }

  @override
  Future<void> startCapture() async {
    debugPrint("RtlTcpCaptureService: rtl_tcp is not supported on web.");
  }

  @override
  Future<void> stopCapture() async {}

  @override
  void dispose() {
    _dataController.close();
  }
}
