import 'dart:typed_data';

class AudioUtils {
  /// Converts 16-bit PCM (Little Endian) bytes to normalized double samples [-1.0, 1.0].
  static Float64List convertPcmToDouble(Uint8List audioData) {
    // If the offset is not a multiple of 2, asInt16List will throw.
    // In such cases, we use ByteData to read the samples safely.
    if (audioData.offsetInBytes % 2 != 0) {
      final byteData = ByteData.view(audioData.buffer, audioData.offsetInBytes, audioData.length);
      final count = audioData.length ~/ 2;
      final samples = Float64List(count);
      for (var i = 0; i < count; i++) {
        samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }
      return samples;
    }

    final int16Data = audioData.buffer.asInt16List(audioData.offsetInBytes, audioData.length ~/ 2);
    final samples = Float64List(int16Data.length);
    for (var i = 0; i < int16Data.length; i++) {
      samples[i] = int16Data[i] / 32768.0;
    }
    return samples;
  }
}
