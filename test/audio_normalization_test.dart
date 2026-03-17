import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:spectral/src/utils/audio_utils.dart';

void main() {
  group('Audio Data Normalization', () {
    test('converts 16-bit PCM to normalized double', () {
      final data = Uint8List.fromList([0, 0]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples.length, 1);
      expect(samples[0], 0.0);
    });

    test('converts max 16-bit PCM to 1.0 (approx)', () {
      final data = Uint8List.fromList([0xFF, 0x7F]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples[0], closeTo(32767 / 32768.0, 0.0001));
    });

    test('converts min 16-bit PCM to -1.0', () {
      final data = Uint8List.fromList([0x00, 0x80]);
      final samples = AudioUtils.convertPcmToDouble(data);

      expect(samples[0], -1.0);
    });
  });
}
