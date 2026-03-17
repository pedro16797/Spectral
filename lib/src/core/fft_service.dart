import 'dart:typed_data';
import 'package:fftea/fftea.dart';

class FftService {
  FFT? _cachedFft;
  int? _cachedSize;

  /// Processes normalized audio samples and returns the FFT magnitudes.
  List<double> processAudioData(Float64List samples) {
    if (samples.isEmpty) return [];

    final sampleCount = samples.length;
    if (sampleCount < 2) return [];

    // Cache FFT instance if the size hasn't changed.
    // Precomputing tables is expensive.
    if (_cachedFft == null || _cachedSize != sampleCount) {
      _cachedFft = FFT(sampleCount);
      _cachedSize = sampleCount;
    }

    try {
      final freq = _cachedFft!.realFft(samples);
      return freq.magnitudes();
    } catch (e) {
      // In case of unexpected signal errors
      return [];
    }
  }
}
