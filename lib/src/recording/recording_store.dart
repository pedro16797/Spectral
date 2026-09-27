import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../core/signal_source.dart';
import 'recording_format.dart';

export 'recording_format.dart' show RecordingInfo, RecordingFormat;

/// Receives the raw source stream while a recording is running.
abstract class RecordingSink {
  /// Appends a frame exactly as the source delivered it: real samples, or
  /// interleaved I/Q. Frames past the size cap ([kMaxRecordingBytes] by
  /// default) are dropped and [isFull] flips so the owner can stop the
  /// recording.
  void add(Float64List samples);

  int get bytesWritten;
  Duration get duration;
  bool get isFull;

  /// Flushes and finalizes the file, returning its library entry.
  Future<RecordingInfo> close();
}

/// The recordings library: where captures are written, listed, played back,
/// shared and deleted. Needs a filesystem, so web builds get an unsupported
/// implementation and hide the feature.
abstract class RecordingStore {
  bool get isSupported;

  Future<RecordingSink> startRecording({
    required int sampleRate,
    required bool isComplex,
    double? centerFrequencyHz,
  });

  /// Library entries, newest first.
  Future<List<RecordingInfo>> list();

  /// A source that replays [info] in real time, looping at the end.
  SignalSource openPlayback(RecordingInfo info);

  Future<void> delete(RecordingInfo info);

  /// Hands the files to the platform share sheet. [origin] anchors the popover
  /// on iPad, where sharing without one throws.
  Future<void> share(RecordingInfo info, {Rect? origin});

  /// Saves a spectrum CSV into the library.
  Future<RecordingInfo> saveCsv(String csv);
}
