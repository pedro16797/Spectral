import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import '../core/signal_source.dart';

class MockFileSignalSource implements SignalSource {
  final String assetPath;
  final bool _isComplex;
  final int _sampleRate;

  final _dataController = StreamController<Float64List>.broadcast();
  Timer? _timer;
  Uint8List? _rawData;
  int _offset = 0;
  static const int _chunkSize = 1024;

  MockFileSignalSource({
    required this.assetPath,
    required bool isComplex,
    required int sampleRate,
  })  : _isComplex = isComplex,
        _sampleRate = sampleRate;

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
    _rawData ??= (await rootBundle.load(assetPath)).buffer.asUint8List();

    // Skip WAV header if needed (simple check)
    if (assetPath.endsWith('.wav') && _offset == 0) {
      _offset = 44; // Standard WAV header size
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_rawData == null) return;

      final int bytesPerSample = isComplex ? 8 : 2; // Float32 IQ (4+4) or Int16 Mono (2)
      final int samplesToRead = _chunkSize;
      final int bytesToRead = samplesToRead * bytesPerSample;

      if (_offset + bytesToRead > _rawData!.length) {
        _offset = assetPath.endsWith('.wav') ? 44 : 0;
      }

      final samples = Float64List(isComplex ? samplesToRead * 2 : samplesToRead);
      final view = ByteData.sublistView(_rawData!, _offset, _offset + bytesToRead);

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

      _dataController.add(samples);
      _offset += bytesToRead;
    });
  }

  @override
  Future<void> stopCapture() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stopCapture();
    _dataController.close();
  }
}
