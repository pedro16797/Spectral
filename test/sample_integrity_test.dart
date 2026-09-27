import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/recording/recording_format.dart';

void main() {
  group('Sample Integrity Tests', () {
    test('Sine wave audio sample exists and is non-empty', () {
      final file = File('resources/samples/audio/sine_440_880.wav');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));
    });

    test('chirp sample loops without a seam', () {
      final bytes = File('resources/samples/audio/chirp_sweep.wav').readAsBytesSync();
      final layout = parseWavHeader(bytes, fileLength: bytes.length)!;
      expect(layout.sampleRate, 44100);

      final view = ByteData.sublistView(bytes, layout.dataOffset);
      final int n = layout.dataBytes ~/ 2;
      // The file player reads 1024 samples at a time and skips a partial
      // read at the end, which would cut the waveform mid-cycle.
      expect(n % 1024, 0);

      int sample(int i) => view.getInt16(i * 2, Endian.little);
      // The sweep is slowest at the loop point, so compare the wrap against
      // steps near it: the whole file's largest step (at 15 kHz) would hide a
      // real seam.
      int largestStep = 0;
      for (final i in [
        for (int k = 1; k < 1024; k++) k,
        for (int k = n - 1023; k < n; k++) k,
      ]) {
        final step = (sample(i) - sample(i - 1)).abs();
        if (step > largestStep) largestStep = step;
      }
      // Wrapping from the last sample to the first is just another step.
      expect((sample(0) - sample(n - 1)).abs(), lessThanOrEqualTo(largestStep));
    });

    test('FM IQ sample exists and is non-empty', () {
      final file = File('resources/samples/rf/fm_multi_signals.iq');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000000)); // Should be ~8MB
    });
  });
}
