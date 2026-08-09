import 'dart:typed_data';

class AudioUtils {
  /// Converts 16-bit PCM (Little Endian) bytes to normalized double samples [-1.0, 1.0].
  /// [target] can be provided to reuse an existing buffer and reduce allocations.
  ///
  /// The returned list always has length exactly equal to the number of samples
  /// decoded. [target] is only reused when its length matches exactly; otherwise a
  /// new buffer is allocated. This prevents stale trailing samples from leaking
  /// through when an oversized buffer is reused for a smaller chunk.
  static Float64List convertPcmToDouble(Uint8List audioData, {Float64List? target}) {
    final int count = audioData.length ~/ 2;
    final samples = (target != null && target.length == count) ? target : Float64List(count);

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

  /// Decimates by averaging each group of [factor] input samples — a simple
  /// boxcar (moving-average) anti-alias low-pass before downsampling, which
  /// keeps wideband noise from folding back into the audible band.
  ///
  /// The returned list has length exactly [input.length ~/ factor]; [target]
  /// is reused only on an exact length match (see [convertPcmToDouble]).
  static Float64List decimateAveraged(Float64List input, int factor, {Float64List? target}) {
    if (factor <= 1) return input;
    final int targetLength = input.length ~/ factor;
    final output = (target != null && target.length == targetLength) ? target : Float64List(targetLength);

    final double inv = 1.0 / factor;
    for (int i = 0; i < targetLength; i++) {
      final int base = i * factor;
      double sum = 0.0;
      for (int j = 0; j < factor; j++) {
        sum += input[base + j];
      }
      output[i] = sum * inv;
    }
    return output;
  }
}
