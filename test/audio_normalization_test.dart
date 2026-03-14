import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

void main() {
  group('Audio Data Normalization', () {
    test('converts 16-bit PCM to normalized double', () {
      // 0 in 16-bit PCM
      final data = Uint8List.fromList([0, 0]);
      final byteLow = data[0];
      final byteHigh = data[1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;
      final normalized = sample / 32768.0;

      expect(normalized, 0.0);
    });

    test('converts max 16-bit PCM to 1.0 (approx)', () {
      // 32767 in 16-bit PCM (Little Endian: FF 7F)
      final data = Uint8List.fromList([0xFF, 0x7F]);
      final byteLow = data[0];
      final byteHigh = data[1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;
      final normalized = sample / 32768.0;

      expect(normalized, closeTo(32767 / 32768.0, 0.0001));
    });

    test('converts min 16-bit PCM to -1.0', () {
      // -32768 in 16-bit PCM (Little Endian: 00 80)
      final data = Uint8List.fromList([0x00, 0x80]);
      final byteLow = data[0];
      final byteHigh = data[1];
      var sample = (byteHigh << 8) | byteLow;
      if (sample > 32767) sample -= 65536;
      final normalized = sample / 32768.0;

      expect(normalized, -1.0);
    });
  });
}
