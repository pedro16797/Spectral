import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/utils/mock_file_signal_source.dart';

void main() {
  test('MockFileSignalSource metadata is correct', () {
    final source = MockFileSignalSource(
      assetPath: 'resources/samples/audio/sine_440_880.wav',
      isComplex: false,
      sampleRate: 44100,
    );

    expect(source.isComplex, isFalse);
    expect(source.sampleRate, 44100);
  });

  test('MockFileSignalSource SDR metadata is correct', () {
    final source = MockFileSignalSource(
      assetPath: 'resources/samples/rf/fm_multi_signals.iq',
      isComplex: true,
      sampleRate: 1000000,
    );

    expect(source.isComplex, isTrue);
    expect(source.sampleRate, 1000000);
  });
}
