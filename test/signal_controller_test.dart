import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/core/signal_controller.dart';
import 'package:spectral/src/core/signal_source.dart';
import 'package:spectral/src/recording/recording_store.dart';

/// A controllable signal source for driving the controller in tests, without
/// touching real audio/RF plugins.
class FakeSignalSource implements SignalSource {
  FakeSignalSource({this.isComplex = false, this.sampleRate = 44100});

  final _controller = StreamController<Float64List>.broadcast();

  @override
  final bool isComplex;
  @override
  final int sampleRate;

  bool started = false;
  bool disposed = false;
  bool permission = true;

  /// When set, [checkPermission] awaits this gate, letting tests suspend a
  /// capture toggle and dispose the controller mid-flight.
  Completer<bool>? permissionGate;

  void emit(Float64List data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  @override
  Stream<Float64List> get dataStream => _controller.stream;

  @override
  Future<bool> checkPermission() async {
    if (permissionGate != null) return permissionGate!.future;
    return permission;
  }

  @override
  Future<void> startCapture() async => started = true;

  @override
  Future<void> stopCapture() async => started = false;

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}

class FakeRecordingSink implements RecordingSink {
  FakeRecordingSink(this.info);
  final RecordingInfo info;
  final List<Float64List> frames = [];
  bool closed = false;
  bool full = false;

  @override
  void add(Float64List samples) => frames.add(samples);
  @override
  int get bytesWritten => frames.fold(0, (n, f) => n + f.length * 2);
  @override
  Duration get duration => Duration.zero;
  @override
  bool get isFull => full;
  @override
  Future<RecordingInfo> close() async {
    closed = true;
    return info;
  }
}

class FakeRecordingStore implements RecordingStore {
  final List<FakeRecordingSink> sinks = [];
  final List<FakeSignalSource> playbackSources = [];
  List<RecordingInfo> entries = [];

  @override
  bool get isSupported => true;

  @override
  Future<RecordingSink> startRecording({
    required int sampleRate,
    required bool isComplex,
    double? centerFrequencyHz,
  }) async {
    final sink = FakeRecordingSink(RecordingInfo(
      name: 'rec${sinks.length}',
      format: isComplex ? RecordingFormat.sigmf : RecordingFormat.wav,
      dataPath: 'rec${sinks.length}',
      sampleRate: sampleRate,
      isComplex: isComplex,
      centerFrequencyHz: centerFrequencyHz,
      createdAt: DateTime(2026),
    ));
    sinks.add(sink);
    return sink;
  }

  @override
  Future<List<RecordingInfo>> list() async => entries;

  @override
  SignalSource openPlayback(RecordingInfo info) {
    final src =
        FakeSignalSource(isComplex: info.isComplex, sampleRate: info.sampleRate);
    playbackSources.add(src);
    return src;
  }

  @override
  Future<void> delete(RecordingInfo info) async {}
  @override
  Future<void> share(RecordingInfo info, {Rect? origin}) async {}
  @override
  Future<RecordingInfo> saveCsv(String csv) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Yields long enough for the controller's async reconfigure and the
  // broadcast stream delivery to complete.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  SignalController makeController(
    AppSettings settings,
    void Function(FakeSignalSource) capture, {
    bool isComplex = false,
    int sampleRate = 44100,
  }) {
    return SignalController(
      settings: settings,
      sourceFactory: (s, playFile) {
        final src = FakeSignalSource(isComplex: isComplex, sampleRate: sampleRate);
        capture(src);
        return src;
      },
    );
  }

  group('spectrum view toggle', () {
    // A complex SDR source with FM demodulation is the only configuration in
    // which the two views differ.
    const sdr = AppSettings(
      signalSource: SignalSourceType.rf,
      rfSource: RfSourceType.mock,
      centerFrequency: 100.0,
      rfBandwidth: 2.0,
      demodulationMode: DemodulationMode.fm,
    );

    test('defaults to the RF band', () async {
      final c = makeController(sdr, (_) {},
          isComplex: true, sampleRate: 2000000);
      await settle();
      expect(c.isShowingDemodulated, isFalse);
      expect(c.analysisSampleRate, 2000000);
      // The RF axis is centred on the tuned frequency.
      expect(c.analysisBandHz.start, closeTo(99e6, 1));
      expect(c.analysisBandHz.end, closeTo(101e6, 1));
      c.dispose();
    });

    test('the demodulated view switches to an audio axis', () async {
      final c = makeController(sdr, (_) {},
          isComplex: true, sampleRate: 2000000);
      await settle();
      c.setTunedBand(99.9e6, 100.1e6); // a 200 kHz channel
      c.updateSettings(sdr.copyWith(spectrumView: SpectrumView.demodulated));
      await settle();

      expect(c.isShowingDemodulated, isTrue);
      // The channel rate, not the capture rate.
      expect(c.analysisSampleRate, lessThan(2000000));
      // A real spectrum starts at DC rather than at an RF centre frequency.
      expect(c.analysisBandHz.start, 0);
      expect(c.analysisBandHz.end, closeTo(c.analysisSampleRate / 2, 1));
      c.dispose();
    });

    test('the toggle is inert without a demodulation mode', () async {
      final c = makeController(
        sdr.copyWith(demodulationMode: DemodulationMode.none),
        (_) {},
        isComplex: true,
        sampleRate: 2000000,
      );
      await settle();
      c.updateSettings(sdr.copyWith(
        demodulationMode: DemodulationMode.none,
        spectrumView: SpectrumView.demodulated,
      ));
      await settle();
      // Nothing to demodulate, so the RF band stays on screen.
      expect(c.isShowingDemodulated, isFalse);
      c.dispose();
    });

    test('an audio source never enters the demodulated view', () async {
      final c = makeController(
        const AppSettings(spectrumView: SpectrumView.demodulated),
        (_) {},
      );
      await settle();
      expect(c.isShowingDemodulated, isFalse);
      c.dispose();
    });

    test('switching views drops accumulated analysis state', () async {
      late FakeSignalSource src;
      final c = makeController(sdr, (s) => src = s,
          isComplex: true, sampleRate: 2000000);
      c.setTunedBand(99.9e6, 100.1e6);
      await settle();

      src.emit(Float64List.fromList(List<double>.filled(8192, 0.5)));
      await settle();
      expect(c.currentFftData, isNotEmpty);

      c.updateSettings(sdr.copyWith(spectrumView: SpectrumView.demodulated));
      // Peaks and history belong to the old spectrum, on a different axis;
      // carrying them over would paint phantom signals.
      expect(c.currentFftData, isEmpty);
      expect(c.fftHistory, isEmpty);
      expect(c.detectedTone, isNull);
      expect(c.snr, isNull);
      c.dispose();
    });

    test('the tuned channel survives a round trip through both views', () async {
      final c = makeController(sdr, (_) {},
          isComplex: true, sampleRate: 2000000);
      await settle();
      c.setTunedBand(99.9e6, 100.1e6);

      c.updateSettings(sdr.copyWith(spectrumView: SpectrumView.demodulated));
      await settle();
      c.updateSettings(sdr.copyWith(spectrumView: SpectrumView.rf));
      await settle();

      // Toggling the view must not cost the user their station.
      expect(c.tunedBandHz?.start, closeTo(99.9e6, 1));
      expect(c.tunedBandHz?.end, closeTo(100.1e6, 1));
      c.dispose();
    });
  });

  test('applies gain to real audio samples', () async {
    late FakeSignalSource src;
    final c = makeController(const AppSettings(), (s) => src = s);
    c.gain = 2.0;
    await settle();

    src.emit(Float64List.fromList([0.1, -0.2, 0.3]));
    await settle();

    expect(c.currentAudioData, [
      closeTo(0.2, 1e-9),
      closeTo(-0.4, 1e-9),
      closeTo(0.6, 1e-9),
    ]);
    c.dispose();
  });

  test('AM demodulation outputs envelope magnitude', () async {
    late FakeSignalSource src;
    final c = makeController(
      const AppSettings(
        signalSource: SignalSourceType.rf,
        rfSource: RfSourceType.mock,
        demodulationMode: DemodulationMode.am,
      ),
      (s) => src = s,
      isComplex: true,
      sampleRate: 1000,
    );
    await settle();

    // Interleaved I/Q: (3,4) -> magnitude 5; (0,0) -> 0.
    src.emit(Float64List.fromList([3, 4, 0, 0]));
    await settle();

    expect(c.currentAudioData, [closeTo(5, 1e-9), closeTo(0, 1e-9)]);
    c.dispose();
  });

  test('exposes the active source sampleRate and isComplex', () async {
    late FakeSignalSource src;
    final c = makeController(
      const AppSettings(signalSource: SignalSourceType.rf, rfSource: RfSourceType.mock),
      (s) => src = s,
      isComplex: true,
      sampleRate: 2048000,
    );
    await settle();

    expect(c.sampleRate, 2048000);
    expect(c.isComplex, true);
    expect(src.disposed, false);
    c.dispose();
  });

  test('audio history is capped', () async {
    late FakeSignalSource src;
    final c = makeController(const AppSettings(), (s) => src = s);
    await settle();

    for (int i = 0; i < 12; i++) {
      src.emit(Float64List.fromList([i.toDouble()]));
      await settle();
    }

    expect(c.audioHistory.length, lessThanOrEqualTo(5));
    c.dispose();
  });

  test('toggleCapture starts capture, then stops and clears state', () async {
    late FakeSignalSource src;
    final c = makeController(const AppSettings(), (s) => src = s);
    await settle();
    expect(c.isCapturing, false);

    await c.toggleCapture();
    expect(c.isCapturing, true);
    expect(src.started, true);

    src.emit(Float64List.fromList([0.5, 0.6]));
    await settle();
    expect(c.currentAudioData.isNotEmpty, true);

    await c.toggleCapture();
    expect(c.isCapturing, false);
    expect(src.started, false);
    expect(c.currentAudioData.isEmpty, true);
    expect(c.audioHistory.isEmpty, true);
    c.dispose();
  });

  test('does not start capture when permission is denied', () async {
    late FakeSignalSource src;
    final c = makeController(const AppSettings(), (s) => src = s);
    await settle();
    src.permission = false;

    await c.toggleCapture();
    expect(c.isCapturing, false);
    expect(src.started, false);
    c.dispose();
  });

  test('does not mutate state when disposed mid-capture-toggle', () async {
    late FakeSignalSource src;
    final gate = Completer<bool>();
    final c = makeController(const AppSettings(), (s) {
      s.permissionGate = gate;
      src = s;
    });
    await settle();

    // Begin a toggle; it suspends awaiting the permission gate.
    final pending = c.toggleCapture();
    // Dispose while the toggle is in flight, then let permission resolve.
    c.dispose();
    gate.complete(true);
    await pending;

    // The disposed controller must not have started capturing.
    expect(c.isCapturing, false);
    expect(src.started, false);
  });

  test('notifies listeners when capture state changes', () async {
    final c = makeController(const AppSettings(), (_) {});
    await settle();

    int notifications = 0;
    c.addListener(() => notifications++);

    await c.toggleCapture();
    expect(notifications, greaterThan(0));
    c.dispose();
  });

  test('waterfall speed gates how fast fftHistory accumulates', () async {
    Future<int> rowsAfterFrames(double speed) async {
      late FakeSignalSource src;
      final c = makeController(const AppSettings(), (s) => src = s);
      c.waterfallSpeed = speed;
      await settle();
      // A chunk large enough to yield one FFT frame per emit (windowSize 1024).
      final chunk = Float64List(2048)..fillRange(0, 2048, 0.5);
      for (int f = 0; f < 6; f++) {
        src.emit(chunk);
        await settle();
      }
      final rows = c.fftHistory.length;
      c.dispose();
      return rows;
    }

    final fast = await rowsAfterFrames(5.0); // a row every frame
    final slow = await rowsAfterFrames(0.1); // a row only every ~40 frames
    expect(fast, greaterThan(slow));
    expect(slow, 0);
  });

  test('a waterfall row averages every frame in its slot', () async {
    late FakeSignalSource src;
    final c = makeController(const AppSettings(), (s) => src = s);
    c.waterfallSpeed = 2.0; // One row per 2 frames.
    await settle();

    // Constant (DC) chunks: the FFT's DC bin scales linearly with amplitude,
    // and each chunk fills the 1024-point window on its own.
    Float64List chunk(double v) => Float64List(2048)..fillRange(0, 2048, v);

    src.emit(chunk(0.2));
    await settle();
    final double dcLow = c.currentFftData.first;
    expect(c.fftHistory, isEmpty, reason: 'slot not full yet');

    src.emit(chunk(0.6));
    await settle();
    final double dcHigh = c.currentFftData.first;
    expect(dcHigh, closeTo(dcLow * 3, dcLow * 1e-6));

    expect(c.fftHistory, hasLength(1));
    expect(c.fftHistory.single.first, closeTo((dcLow + dcHigh) / 2, 1e-9),
        reason: 'the mean of the slot, not its last snapshot');

    // The accumulator starts over for the next slot.
    src.emit(chunk(0.2));
    await settle();
    src.emit(chunk(0.2));
    await settle();
    expect(c.fftHistory, hasLength(2));
    expect(c.fftHistory.first.first, closeTo(dcLow, 1e-9));
    c.dispose();
  });

  group('recording, playback and export', () {
    late FakeRecordingStore store;
    setUp(() => store = FakeRecordingStore());

    SignalController make(
      AppSettings settings,
      void Function(FakeSignalSource) capture, {
      bool isComplex = false,
      int sampleRate = 44100,
    }) {
      return SignalController(
        settings: settings,
        recordingStore: store,
        sourceFactory: (s, playFile) {
          final src =
              FakeSignalSource(isComplex: isComplex, sampleRate: sampleRate);
          capture(src);
          return src;
        },
      );
    }

    test('records only while a live capture runs', () async {
      late FakeSignalSource src;
      final c = make(const AppSettings(), (s) => src = s);
      await settle();
      expect(c.canRecord, isFalse);
      expect(await c.startRecording(), isFalse);

      await c.toggleCapture();
      expect(await c.startRecording(), isTrue);
      expect(c.isRecording, isTrue);

      final frame = Float64List.fromList([0.1, 0.2, 0.3]);
      src.emit(frame);
      await settle();
      expect(store.sinks.single.frames.single, same(frame),
          reason: 'the raw source frame, before gain or demodulation');

      await c.toggleCapture();
      expect(c.isRecording, isFalse);
      expect(store.sinks.single.closed, isTrue,
          reason: 'stopping capture finalizes the file');
      c.dispose();
    });

    test('an I/Q recording carries the tuned centre and capture rate', () async {
      final c = make(const AppSettings(signalSource: SignalSourceType.rf,
          centerFrequency: 433.92), (_) {}, isComplex: true, sampleRate: 1024000);
      await settle();
      await c.toggleCapture();
      await c.startRecording();
      final info = store.sinks.single.info;
      expect(info.isComplex, isTrue);
      expect(info.sampleRate, 1024000);
      expect(info.centerFrequencyHz, closeTo(433.92e6, 1));
      c.dispose();
    });

    test('a full sink stops the recording by itself', () async {
      late FakeSignalSource src;
      final c = make(const AppSettings(), (s) => src = s);
      await settle();
      await c.toggleCapture();
      await c.startRecording();
      store.sinks.single.full = true;
      src.emit(Float64List(4));
      await settle();
      expect(c.isRecording, isFalse);
      expect(store.sinks.single.closed, isTrue);
      c.dispose();
    });

    test('reconfiguring the source ends the recording', () async {
      final c = make(const AppSettings(), (_) {});
      await settle();
      await c.toggleCapture();
      await c.startRecording();
      await c.reconfigure();
      expect(c.isRecording, isFalse);
      expect(store.sinks.single.closed, isTrue);
      c.dispose();
    });

    test('playback swaps in the recording and uses its own tuning', () async {
      final live = <FakeSignalSource>[];
      // Settings say audio; the recording is an I/Q capture at 145 MHz.
      final c = make(const AppSettings(), live.add);
      await settle();
      final recording = RecordingInfo(
        name: 'iq',
        format: RecordingFormat.sigmf,
        dataPath: 'iq.sigmf-data',
        metaPath: 'iq.sigmf-meta',
        sampleRate: 2000000,
        isComplex: true,
        centerFrequencyHz: 145e6,
        dataBytes: 4000,
        createdAt: DateTime(2026),
      );

      await c.startPlayback(recording);
      final playback = store.playbackSources.single;
      expect(c.playbackRecording, same(recording));
      expect(playback.started, isTrue, reason: 'playback starts capturing');
      expect(live.single.disposed, isTrue);
      expect(c.isComplex, isTrue);
      expect(c.centerFrequencyHz, 145e6);
      expect(c.analysisBandHz.start, 144e6);
      expect(c.analysisBandHz.end, 146e6);
      expect(c.canRecord, isFalse, reason: 'no re-recording a recording');

      await c.stopPlayback();
      expect(c.playbackRecording, isNull);
      expect(c.isCapturing, isFalse);
      expect(playback.disposed, isTrue);
      expect(live, hasLength(2), reason: 'back on a fresh live source');
      expect(c.isComplex, isFalse);
      c.dispose();
    });

    test('CSV export follows the analysed spectrum', () async {
      late FakeSignalSource src;
      final c = make(const AppSettings(), (s) => src = s);
      await settle();
      expect(c.hasSpectrum, isFalse);
      expect(c.spectrumCsv(), isNull);

      await c.toggleCapture();
      c.sensitivity = 3.0;
      src.emit(Float64List(2048)..fillRange(0, 2048, 0.5));
      await settle();
      expect(c.hasSpectrum, isTrue);

      final lines = c.spectrumCsv()!.trim().split('\n');
      expect(lines.first, 'frequency_hz,magnitude,magnitude_db');
      // A 1024-point real FFT: 513 bins from 0 Hz to Nyquist.
      expect(lines, hasLength(1 + 513));
      expect(lines.last, startsWith('22050.0,'));
      // Exported without the sensitivity display scale.
      final dc = double.parse(lines[1].split(',')[1]);
      expect(dc, closeTo(c.currentFftData.first / 3.0, 1e-3));

      await c.toggleCapture();
      expect(c.hasSpectrum, isFalse,
          reason: 'nothing on screen, nothing to export');
      c.dispose();
    });
  });
}
