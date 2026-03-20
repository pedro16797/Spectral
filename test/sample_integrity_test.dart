import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sample Integrity Tests', () {
    test('Sine wave audio sample exists and is non-empty', () {
      final file = File('resources/samples/audio/sine_440_880.wav');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));
    });

    test('FM IQ sample exists and is non-empty', () {
      final file = File('resources/samples/rf/fm_multi_signals.iq');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000000)); // Should be ~8MB
    });
  });
}
