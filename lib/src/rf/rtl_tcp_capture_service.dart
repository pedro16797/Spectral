import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';

/// Implementation of the rtl_tcp protocol for external SDR hardware.
/// Streams raw I/Q data from a remote (or local) rtl_tcp server.
class RtlTcpCaptureService implements SignalSource {
  final String host;
  final int port;
  final int _requestedSampleRate;
  final int _requestedFrequency;

  Socket? _socket;
  final _dataController = StreamController<Float64List>.broadcast();
  bool _isCapturing = false;
  bool _headerSkipped = false;

  RtlTcpCaptureService({
    this.host = '127.0.0.1',
    this.port = 1234,
    int sampleRate = 2048000,
    int frequency = 100000000,
  })  : _requestedSampleRate = sampleRate,
        _requestedFrequency = frequency;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => _requestedSampleRate;

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async => true; // Network doesn't require specific permissions in this context

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _isCapturing = true;
      _headerSkipped = false;

      // Initialize RTL-SDR parameters
      _setFrequency(_requestedFrequency);
      _setSampleRate(_requestedSampleRate);

      _socket!.listen(
        (data) {
          _processRawData(data);
        },
        onDone: () => stopCapture(),
        onError: (e) {
          debugPrint("RTL_TCP Socket Error: $e");
          stopCapture();
        },
      );
    } catch (e) {
      debugPrint("Failed to connect to rtl_tcp: $e");
      _isCapturing = false;
      rethrow;
    }
  }

  final List<int> _headerBuffer = [];

  void _processRawData(Uint8List data) {
    int offset = 0;
    if (!_headerSkipped) {
      // rtl_tcp sends a 12-byte header: 'RTL0' + info
      int toCopy = math.min(12 - _headerBuffer.length, data.length);
      _headerBuffer.addAll(data.sublist(0, toCopy));
      offset = toCopy;

      if (_headerBuffer.length == 12) {
        _headerSkipped = true;
        _headerBuffer.clear();
      } else {
        // Wait for more data
        return;
      }
    }

    final remaining = data.length - offset;
    if (remaining <= 0) return;

    // Convert uint8 I/Q [0, 255] to double [-1.0, 1.0]
    final doubleSamples = Float64List(remaining);
    for (int i = 0; i < remaining; i++) {
      doubleSamples[i] = (data[offset + i] - 127.5) / 127.5;
    }
    _dataController.add(doubleSamples);
  }

  void _sendCommand(int cmd, int arg) {
    if (_socket == null) return;
    final buffer = Uint8List(5);
    buffer[0] = cmd;
    // Big-endian argument
    buffer[1] = (arg >> 24) & 0xFF;
    buffer[2] = (arg >> 16) & 0xFF;
    buffer[3] = (arg >> 8) & 0xFF;
    buffer[4] = arg & 0xFF;
    _socket!.add(buffer);
  }

  void _setFrequency(int hz) => _sendCommand(0x01, hz);
  void _setSampleRate(int hz) => _sendCommand(0x02, hz);

  @override
  Future<void> stopCapture() async {
    if (!_isCapturing) return;
    _isCapturing = false;
    await _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
