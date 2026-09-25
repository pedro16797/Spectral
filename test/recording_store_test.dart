import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/recording/recording_format.dart';
import 'package:spectral/src/recording/recording_store_io.dart';

void main() {
  late Directory dir;
  late IoRecordingStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('spectral_recordings_');
    store = IoRecordingStore(directory: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Float64List ramp(int n, {double scale = 1}) =>
      Float64List.fromList([for (int i = 0; i < n; i++) scale * (i % 100) / 100]);

  test('an audio recording becomes a patched, playable WAV', () async {
    final sink = await store.startRecording(sampleRate: 8000, isComplex: false);
    sink.add(ramp(4000));
    sink.add(ramp(4000));
    expect(sink.duration, const Duration(seconds: 1));
    final saved = await sink.close();

    expect(saved.format, RecordingFormat.wav);
    expect(saved.dataBytes, 16000);

    final bytes = await File(saved.dataPath).readAsBytes();
    expect(bytes.length, kWavHeaderBytes + 16000);
    // The size fields were patched in place, not appended.
    final layout = parseWavHeader(bytes, fileLength: bytes.length)!;
    expect(layout.dataBytes, 16000);
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 36 + 16000);

    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.sampleRate, 8000);
    expect(listed.single.duration, const Duration(seconds: 1));
    expect(listed.single.isPlayable, isTrue);
  });

  test('an I/Q recording becomes a SigMF pair carrying its tuning', () async {
    final sink = await store.startRecording(
        sampleRate: 250000, isComplex: true, centerFrequencyHz: 433.92e6);
    sink.add(ramp(1000)); // 500 I/Q pairs.
    final saved = await sink.close();

    expect(saved.format, RecordingFormat.sigmf);
    expect(saved.paths, hasLength(2));
    expect(saved.dataPath, endsWith(kSigmfDataExtension));
    expect(saved.metaPath, endsWith(kSigmfMetaExtension));

    final listed = (await store.list()).single;
    expect(listed.isComplex, isTrue);
    expect(listed.sampleRate, 250000);
    expect(listed.centerFrequencyHz, 433.92e6);
    expect(listed.dataBytes, 2000);
  });

  test('delete removes every file of an entry', () async {
    final sink = await store.startRecording(
        sampleRate: 1000, isComplex: true, centerFrequencyHz: 1e6);
    sink.add(ramp(10));
    final saved = await sink.close();
    await store.delete(saved);
    expect(await dir.list().toList(), isEmpty);
  });

  test('CSV exports are listed but not playable', () async {
    await store.saveCsv('frequency_hz,magnitude,magnitude_db\n0.0,1,0\n');
    final listed = (await store.list()).single;
    expect(listed.format, RecordingFormat.csv);
    expect(listed.isPlayable, isFalse);
  });

  test('unrelated and unreadable files are skipped', () async {
    await File('${dir.path}/notes.txt').writeAsString('hi');
    await File('${dir.path}/broken.wav').writeAsString('not a wav');
    // A sidecar whose data file is missing.
    await File('${dir.path}/orphan$kSigmfMetaExtension').writeAsString(
        buildSigmfMeta(
            sampleRate: 1000, centerFrequencyHz: 0, startedAt: DateTime(2026)));
    expect(await store.list(), isEmpty);
  });

  test('playback replays the recorded samples and loops', () async {
    final sink = await store.startRecording(sampleRate: 4000, isComplex: false);
    final recorded = ramp(400); // 100 ms.
    sink.add(recorded);
    final saved = await sink.close();

    final source = FileRecordingSource(saved,
        tick: const Duration(milliseconds: 5));
    expect(source.sampleRate, 4000);
    expect(source.isComplex, isFalse);

    final received = <double>[];
    final sub = source.dataStream.listen(received.addAll);
    await source.startCapture();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await source.stopCapture();
    await sub.cancel();
    source.dispose();

    // Paced in real time: ~1000 samples in 250 ms, never far ahead of it.
    expect(received.length, greaterThan(400), reason: 'looped past the end');
    expect(received.length, lessThanOrEqualTo(1100));
    for (int i = 0; i < received.length; i++) {
      expect(received[i], closeTo(recorded[i % 400], 1 / 32767));
    }
  });

  test('the size cap truncates at a frame boundary and flags the sink',
      () async {
    final capped = IoRecordingStore(directory: () async => dir, maxRecordingBytes: 10);
    final sink = await capped.startRecording(sampleRate: 1000, isComplex: true);
    sink.add(ramp(4)); // 2 pairs = 8 bytes.
    expect(sink.isFull, isFalse);
    sink.add(ramp(4)); // Only 2 bytes of room: not enough for a whole pair.
    expect(sink.isFull, isTrue);
    sink.add(ramp(4)); // Ignored once full.
    final saved = await sink.close();
    expect(saved.dataBytes, 8);
    expect(await File(saved.dataPath).length(), 8);
  });
}
