import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/utils/mock_file_signal_source.dart';

/// Serves bundled assets straight from the repository.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

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

  test('keeps its frame rate when the event loop is starved', () async {
    final source = MockFileSignalSource(
      assetPath: 'resources/samples/audio/chirp_sweep.wav',
      isComplex: false,
      sampleRate: 44100,
      bundle: _FileBundle(),
    );
    final frames = <Float64List>[];
    final sub = source.dataStream.listen(frames.add);
    await source.startCapture();

    // Hog the event loop for 500 ms, as software rendering in a headless
    // browser does: no timer can fire meanwhile.
    final hog = Stopwatch()..start();
    while (hog.elapsedMilliseconds < 500) {}
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await source.stopCapture();
    await sub.cancel();
    source.dispose();

    // 20 frames/s: ~12 frames were due, delivered once the loop came back,
    // instead of the one or two a tick-per-frame player would manage.
    expect(frames.length, inInclusiveRange(10, 14));
    expect(frames.every((f) => f.length == 1024), isTrue);

    // Contiguous: frame k starts right where frame k-1 ended in the file.
    final bytes = File('resources/samples/audio/chirp_sweep.wav').readAsBytesSync();
    final pcm = ByteData.sublistView(bytes, 44);
    for (int k = 0; k < frames.length; k++) {
      expect(frames[k][0], pcm.getInt16(k * 1024 * 2, Endian.little) / 32768.0);
    }
  });
}
