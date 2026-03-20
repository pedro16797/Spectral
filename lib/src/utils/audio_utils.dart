import 'dart:typed_data';

class AudioUtils {
  /// Converts 16-bit PCM (Little Endian) bytes to normalized double samples [-1.0, 1.0].
  static Float64List convertPcmToDouble(Uint8List audioData) {
    final int16Data = audioData.buffer.asInt16List(audioData.offsetInBytes, audioData.length ~/ 2);
    final samples = Float64List(int16Data.length);
    for (var i = 0; i < int16Data.length; i++) {
      samples[i] = int16Data[i] / 32768.0;
    }
    return samples;
  }
}
