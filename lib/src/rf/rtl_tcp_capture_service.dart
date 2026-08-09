import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../core/signal_source.dart';
import 'rtl2832u.dart';

// The RTL sample conversion is shared with the integrated USB path; re-exported
// so callers (and tests) of this service can keep importing it from here.
export 'rtl2832u.dart' show rtlIqBytesToDouble, RtlIqChunker;

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
  StreamSubscription<Uint8List>? _subscription;
  final _dataController = StreamController<Float64List>.broadcast();
  final RtlIqChunker _chunker = RtlIqChunker();
  bool _isCapturing = false;
  final List<int> _headerBuffer = [];

  static const int _headerLength = 12;

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
    // Claim the flag before awaiting, so an overlapping call cannot open a
    // second socket and leak the first.
    _isCapturing = true;

    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      _socket = socket;
      _headerBuffer.clear();
      _chunker.reset();

      _configureDevice();

      _subscription = socket.listen(
        _processRawData,
        onDone: stopCapture,
        onError: (Object e) {
          debugPrint("RTL_TCP Socket Error: $e");
          stopCapture();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("Failed to connect to rtl_tcp at $host:$port: $e");
      _isCapturing = false;
      _socket?.destroy();
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
    if (_headerBuffer.length < _headerLength) {
      // rtl_tcp prefixes the stream with a 12-byte header ('RTL0' + caps).
      final int toCopy =
          math.min(_headerLength - _headerBuffer.length, data.length);
      _headerBuffer.addAll(data.sublist(0, toCopy));
      offset = toCopy;

      if (_headerBuffer.length < _headerLength) {
        return; // Wait for the rest of the header.
      }

      // Anything that does not open with the 'RTL0' magic is not an rtl_tcp
      // server (wrong port, wrong service, or a hostile endpoint) — drop the
      // connection rather than render its bytes as RF samples.
      if (_headerBuffer[0] != 0x52 || // R
          _headerBuffer[1] != 0x54 || // T
          _headerBuffer[2] != 0x4C || // L
          _headerBuffer[3] != 0x30) { // 0
        debugPrint("rtl_tcp: $host:$port did not send an RTL0 header; "
            "disconnecting.");
        unawaited(stopCapture());
        return;
      }
    }

    if (_dataController.isClosed) return;
    final samples = _chunker.process(data, offset: offset);
    if (samples != null) _dataController.add(samples);
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
    await _subscription?.cancel();
    _subscription = null;
    // destroy() tears down both directions immediately. close() alone only
    // shuts the write side, so the server would keep streaming samples into a
    // subscription nobody wants — and a quick restart would read them.
    _socket?.destroy();
    _socket = null;
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
