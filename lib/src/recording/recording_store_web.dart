import 'dart:ui' show Rect;

import '../core/signal_source.dart';
import 'recording_store.dart';

/// Web builds have no filesystem to record into, so the library is reported
/// as unsupported and the UI hides it. Selected via conditional import so the
/// web build does not pull in `dart:io`.
RecordingStore createRecordingStore() => UnsupportedRecordingStore();

class UnsupportedRecordingStore implements RecordingStore {
  @override
  bool get isSupported => false;

  @override
  Future<RecordingSink> startRecording({
    required int sampleRate,
    required bool isComplex,
    double? centerFrequencyHz,
  }) =>
      throw UnsupportedError('Recording is not available on this platform');

  @override
  Future<List<RecordingInfo>> list() async => const [];

  @override
  SignalSource openPlayback(RecordingInfo info) =>
      throw UnsupportedError('Playback is not available on this platform');

  @override
  Future<void> delete(RecordingInfo info) async {}

  @override
  Future<void> share(RecordingInfo info, {Rect? origin}) async {}

  @override
  Future<RecordingInfo> saveCsv(String csv) =>
      throw UnsupportedError('Export is not available on this platform');
}
