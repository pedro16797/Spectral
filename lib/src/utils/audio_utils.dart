import 'dart:typed_data';

class AudioUtils {
  /// Converts 16-bit PCM (Little Endian) bytes to normalized double samples [-1.0, 1.0].
  static Float64List convertPcmToDouble(Uint8List audioData) {
    final sampleCount = audioData.length ~/ 2;
    final samples = Float64List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final byteLow = audioData[i * 2];
      final byteHigh = audioData[i * 2 + 1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;
      samples[i] = sample / 32768.0;
    }
    return samples;
  }
}
