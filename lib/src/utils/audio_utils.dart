import 'dart:typed_data';

class AudioUtils {
  /// Converts 16-bit PCM (Little Endian) bytes to normalized double samples [-1.0, 1.0].
  /// [target] can be provided to reuse an existing buffer and reduce allocations.
  static Float64List convertPcmToDouble(Uint8List audioData, {Float64List? target}) {
    final int count = audioData.length ~/ 2;
    final samples = (target != null && target.length >= count) ? target : Float64List(count);

    // If the offset is not a multiple of 2, asInt16List will throw.
    // In such cases, we use ByteData to read the samples safely.
    if (audioData.offsetInBytes % 2 != 0) {
      final byteData = ByteData.view(audioData.buffer, audioData.offsetInBytes, audioData.length);
      for (var i = 0; i < count; i++) {
        samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }
      return samples;
    }

    final int16Data = audioData.buffer.asInt16List(audioData.offsetInBytes, count);
    for (var i = 0; i < count; i++) {
      samples[i] = int16Data[i] / 32768.0;
    }
    return samples;
  }

  /// Decimates (downsamples) audio data by an integer factor.
  static Float64List decimate(Float64List input, int factor, {Float64List? target}) {
    if (factor <= 1) return input;
    final int targetLength = input.length ~/ factor;
    final output = (target != null && target.length >= targetLength) ? target : Float64List(targetLength);

    for (int i = 0; i < targetLength; i++) {
      output[i] = input[i * factor];
    }
    return output;
  }
}
