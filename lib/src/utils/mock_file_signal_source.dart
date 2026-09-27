import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import '../core/signal_source.dart';

class MockFileSignalSource implements SignalSource {
  final String assetPath;
  final bool _isComplex;
  final int _sampleRate;

  final AssetBundle? _bundle;
  final _dataController = StreamController<Float64List>.broadcast();
  Timer? _timer;
  Uint8List? _rawData;
  int _offset = 0;
  static const int _chunkSize = 1024;
  static const Duration _framePeriod = Duration(milliseconds: 50);

  /// Frames are due on this clock rather than on timer ticks, so a starved
  /// event loop (a slow device, or a headless browser rendering in software)
  /// still gets every frame, several per late tick, instead of playing slower.
  final Stopwatch _clock = Stopwatch();
  int _framesEmitted = 0;

  /// Longest backlog replayed after a stall; anything older is skipped rather
  /// than flooding the pipeline in one burst.
  static const int _maxCatchUpFrames = 40;

  MockFileSignalSource({
    required this.assetPath,
    required bool isComplex,
    required int sampleRate,
    AssetBundle? bundle,
  })  : _isComplex = isComplex,
        _sampleRate = sampleRate,
        _bundle = bundle;

  @override
  Stream<Float64List> get dataStream => _dataController.stream;

  @override
  int get sampleRate => _sampleRate;

  @override
  bool get isComplex => _isComplex;

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<void> startCapture() async {
    _rawData ??=
        (await (_bundle ?? rootBundle).load(assetPath)).buffer.asUint8List();

    // Skip WAV header if needed (simple check)
    if (assetPath.endsWith('.wav') && _offset == 0) {
      _offset = 44; // Standard WAV header size
    }

    _timer?.cancel();
    _framesEmitted = 0;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(_framePeriod, (timer) {
      int due = _clock.elapsedMicroseconds ~/ _framePeriod.inMicroseconds -
          _framesEmitted;
      if (due > _maxCatchUpFrames) {
        _framesEmitted += due - _maxCatchUpFrames;
        due = _maxCatchUpFrames;
      }
      for (int i = 0; i < due; i++) {
        if (!_emitFrame()) {
          timer.cancel();
          return;
        }
        _framesEmitted++;
      }
    });
  }

  /// Emits the next chunk, looping at the end of the file. Returns false when
  /// the file is too short to fill a single chunk.
  bool _emitFrame() {
    if (_rawData == null) return true;

    final int bytesPerSample =
        isComplex ? 8 : 2; // Float32 IQ (4+4) or Int16 Mono (2)
    final int samplesToRead = _chunkSize;
    final int bytesToRead = samplesToRead * bytesPerSample;

    if (_offset + bytesToRead > _rawData!.length) {
      _offset = assetPath.endsWith('.wav') ? 44 : 0;
      // A file shorter than one chunk can never fill a frame; keep quiet
      // instead of overrunning the buffer on every tick.
      if (_offset + bytesToRead > _rawData!.length) {
        return false;
      }
    }

    final samples = Float64List(isComplex ? samplesToRead * 2 : samplesToRead);
    final view =
        ByteData.sublistView(_rawData!, _offset, _offset + bytesToRead);

    for (int i = 0; i < samplesToRead; i++) {
      if (isComplex) {
        // Float32 IQ
        samples[i * 2] = view.getFloat32(i * 8, Endian.little);
        samples[i * 2 + 1] = view.getFloat32(i * 8 + 4, Endian.little);
      } else {
        // Int16 PCM
        samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
      }
    }

    if (!_dataController.isClosed) _dataController.add(samples);
    _offset += bytesToRead;
    return true;
  }

  @override
  Future<void> stopCapture() async {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
