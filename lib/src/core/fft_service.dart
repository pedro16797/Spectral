import 'dart:typed_data';
import 'package:fftea/fftea.dart';

class FftService {
  /// Processes raw 16-bit PCM audio data and returns the FFT magnitudes.
  /// The output represents the magnitude of each frequency bin.
  List<double> processAudioData(Uint8List audioData) {
    if (audioData.isEmpty) return [];

    // Convert 16-bit PCM to double samples in range [-1.0, 1.0]
    final sampleCount = audioData.length ~/ 2;
    if (sampleCount < 2) return [];

    final samples = Float64List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final byteLow = audioData[i * 2];
      final byteHigh = audioData[i * 2 + 1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;
      samples[i] = sample / 32768.0;
    }

    // Perform FFT. fftea can handle any size, but powers of 2 are fastest.
    final fft = FFT(sampleCount);
    final freq = fft.realFft(samples);

    // Calculate magnitudes. magnitudes() returns a Float64List.
    return freq.magnitudes();
  }
}
