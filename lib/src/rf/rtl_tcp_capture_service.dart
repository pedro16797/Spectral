import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';
import 'rtl2832u.dart';

// The RTL sample conversion is shared with the integrated USB path; re-exported
// so callers (and tests) of this service can keep importing it from here.
export 'rtl2832u.dart' show rtlIqBytesToDouble;

/// rtl_tcp control command opcodes (see librtlsdr's rtl_tcp).
class RtlTcpCommand {
  RtlTcpCommand._();
  static const int setFrequency = 0x01;
  static const int setSampleRate = 0x02;
  static const int setGainMode = 0x03; // 0 = auto, 1 = manual
  static const int setGain = 0x04; // tenths of dB
  static const int setFreqCorrection = 0x05; // ppm
  static const int setAgcMode = 0x08; // 0 = off, 1 = on
  static const int setTunerGainByIndex = 0x0d;
  static const int setBiasTee = 0x0e; // 0 = off, 1 = on
}

/// Builds a 5-byte rtl_tcp command frame: one opcode byte followed by a
/// 32-bit big-endian argument. Negative arguments are encoded as 32-bit
/// two's complement. Pure and side-effect free so it can be unit tested.
Uint8List buildRtlTcpCommand(int cmd, int arg) {
  final buffer = Uint8List(5);
  buffer[0] = cmd & 0xFF;
  buffer[1] = (arg >> 24) & 0xFF;
  buffer[2] = (arg >> 16) & 0xFF;
  buffer[3] = (arg >> 8) & 0xFF;
  buffer[4] = arg & 0xFF;
  return buffer;
}

/// Implementation of the rtl_tcp protocol for external SDR hardware.
///
/// Streams raw I/Q data from a (usually local) rtl_tcp server, which is the
/// standard way to drive a real RTL-SDR dongle from a sandboxed app: on Android
/// a helper driver app exposes the USB dongle on 127.0.0.1:1234, and on desktop
/// the `rtl_tcp` binary does the same.
class RtlTcpCaptureService implements SignalSource {
  final String host;
  final int port;
  final int _requestedSampleRate;
  final int _requestedFrequency;
  final int _ppmCorrection;

  /// Tuner gain in tenths of a dB. When null (default) the tuner runs in
  /// automatic gain mode, which is the simplest "just works" configuration.
  final int? _tunerGainTenthsDb;

  Socket? _socket;
  final _dataController = StreamController<Float64List>.broadcast();
  bool _isCapturing = false;
  bool _headerSkipped = false;
  final List<int> _headerBuffer = [];

  RtlTcpCaptureService({
    this.host = '127.0.0.1',
    this.port = 1234,
    int sampleRate = 2048000,
    int frequency = 100000000,
    int ppmCorrection = 0,
    int? tunerGainTenthsDb,
  })  : _requestedSampleRate = sampleRate,
        _requestedFrequency = frequency,
        _ppmCorrection = ppmCorrection,
        _tunerGainTenthsDb = tunerGainTenthsDb;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => _requestedSampleRate;

  @override
  bool get isComplex => true;

  @override
  Future<bool> checkPermission() async => true; // Network access needs no runtime permission here.

  @override
  Future<void> startCapture() async {
    if (_isCapturing) return;

    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _isCapturing = true;
      _headerSkipped = false;
      _headerBuffer.clear();

      _configureDevice();

      _socket!.listen(
        _processRawData,
        onDone: stopCapture,
        onError: (e) {
          debugPrint("RTL_TCP Socket Error: $e");
          stopCapture();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("Failed to connect to rtl_tcp at $host:$port: $e");
      _isCapturing = false;
      await _socket?.close();
      _socket = null;
      rethrow;
    }
  }

  /// Sends the initial device configuration once connected. Order follows the
  /// usual rtl_tcp setup: rate, frequency, correction, then gain.
  void _configureDevice() {
    _sendCommand(RtlTcpCommand.setSampleRate, _requestedSampleRate);
    _sendCommand(RtlTcpCommand.setFrequency, _requestedFrequency);
    if (_ppmCorrection != 0) {
      _sendCommand(RtlTcpCommand.setFreqCorrection, _ppmCorrection);
    }

    if (_tunerGainTenthsDb != null) {
      // Manual gain: switch to manual mode then set the gain value.
      _sendCommand(RtlTcpCommand.setGainMode, 1);
      _sendCommand(RtlTcpCommand.setGain, _tunerGainTenthsDb);
      _sendCommand(RtlTcpCommand.setAgcMode, 0);
    } else {
      // Automatic gain: tuner AGC plus RTL2832 digital AGC.
      _sendCommand(RtlTcpCommand.setGainMode, 0);
      _sendCommand(RtlTcpCommand.setAgcMode, 1);
    }
  }

  void _processRawData(Uint8List data) {
    int offset = 0;
    if (!_headerSkipped) {
      // rtl_tcp prefixes the stream with a 12-byte header ('RTL0' + caps).
      final int toCopy = math.min(12 - _headerBuffer.length, data.length);
      _headerBuffer.addAll(data.sublist(0, toCopy));
      offset = toCopy;

      if (_headerBuffer.length == 12) {
        _headerSkipped = true;
        _headerBuffer.clear();
      } else {
        return; // Wait for the rest of the header.
      }
    }

    final remaining = data.length - offset;
    if (remaining <= 0) return;
    if (_dataController.isClosed) return;
    _dataController.add(rtlIqBytesToDouble(data, offset, remaining));
  }

  void _sendCommand(int cmd, int arg) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(buildRtlTcpCommand(cmd, arg));
  }

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
