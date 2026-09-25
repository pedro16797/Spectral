import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../audio/audio_capture_service.dart';
import '../audio/audio_output_service.dart';
import '../rf/simulated_rf_capture_service.dart';
import '../rf/rtl_tcp_capture_service.dart'
    if (dart.library.html) '../rf/rtl_tcp_capture_service_stub.dart';
import '../rf/integrated_rf_capture_service.dart';
import '../rf/native_sdr_driver.dart';
import '../rf/rtl2832u.dart';
import '../recording/recording_format.dart' show buildSpectrumCsv;
import '../recording/recording_store.dart';
import '../recording/recording_store_io.dart'
    if (dart.library.html) '../recording/recording_store_web.dart';
import '../utils/audio_utils.dart';
import '../utils/mock_file_signal_source.dart';
import 'audio_filters.dart';
import 'channel_extractor.dart';
import 'signal_source.dart';
import 'fft_service.dart';
import 'settings_model.dart';

/// A tiny [Listenable] used to drive per-frame repaints of the live
/// visualization layers without rebuilding the surrounding widget tree.
class FrameTicker extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Builds a [SignalSource] for the given settings. Injectable so tests can
/// supply a controllable fake without touching audio/RF plugins.
typedef SignalSourceFactory = SignalSource Function(AppSettings settings, String? playFile);

/// The production source selection: a file playback mock, an RF source
/// (rtl_tcp / integrated / simulated), or live audio capture.
SignalSource defaultSignalSourceFactory(AppSettings settings, String? playFile) {
  if (playFile != null) {
    return MockFileSignalSource(
      assetPath: playFile,
      isComplex: settings.signalSource == SignalSourceType.rf,
      sampleRate: settings.signalSource == SignalSourceType.rf
          ? (settings.rfBandwidth * 1e6).toInt()
          : 44100,
    );
  }
  if (settings.signalSource == SignalSourceType.rf) {
    switch (settings.rfSource) {
      case RfSourceType.rtlTcp:
        return RtlTcpCaptureService(
          host: settings.rtlTcpHost,
          port: settings.rtlTcpPort,
          sampleRate: (settings.rfBandwidth * 1e6).toInt(),
          frequency: (settings.centerFrequency * 1e6).toInt(),
          ppmCorrection: settings.ppmCorrection.round(),
        );
      case RfSourceType.integrated:
        return IntegratedRfCaptureService(
          centerFrequency: settings.centerFrequency * 1e6,
          bandwidth: settings.rfBandwidth * 1e6,
          ppmCorrection: settings.ppmCorrection,
        );
      case RfSourceType.mock:
        return SimulatedRfCaptureService(
          centerFrequency: settings.centerFrequency * 1e6,
          bandwidth: settings.rfBandwidth * 1e6,
        );
    }
  }
  return AudioCaptureService();
}

/// Owns the real-time signal pipeline: source lifecycle, demodulation, FFT,
/// and the rolling visualization history. The UI observes [frame] for
/// per-frame repaints and listens to this [ChangeNotifier] for discrete state
/// changes (currently just [isCapturing]).
///
/// Separating per-frame ticks ([frame]) from discrete notifications keeps the
/// expensive glass/blur chrome from rebuilding on every incoming sample frame.
class SignalController extends ChangeNotifier {
  SignalController({
    required AppSettings settings,
    this.isDemoMode = false,
    this.playFile,
    SignalSourceFactory? sourceFactory,
    RecordingStore? recordingStore,
  })  : _settings = settings,
        _sourceFactory = sourceFactory ?? defaultSignalSourceFactory,
        recordingStore = recordingStore ?? createRecordingStore() {
    // The source is created once, inside reconfigure(), which runs synchronously
    // up to installing the stream subscription on this first (non-capturing) call.
    _audioOutputService.init();
    // React to the dongle being plugged in or unplugged while the app is
    // running, rather than only when the user re-enters the RF settings.
    _driverStateSubscription =
        NativeSdrDriver().stateChanges.listen(_onDriverStateChanged);
    reconfigure();
  }

  final bool isDemoMode;
  final String? playFile;
  final SignalSourceFactory _sourceFactory;

  /// Where recordings and CSV exports are kept.
  final RecordingStore recordingStore;

  /// The capture being written, if any. Fed the raw source stream.
  RecordingSink? _recorder;

  /// The recording being replayed in place of the live source, if any.
  RecordingInfo? _playback;

  /// The FFT of the last analysed frame, before the sensitivity display
  /// scale, and whether it was a complex (DC-centred) spectrum. Kept for CSV
  /// export, which should record the signal rather than the dial position.
  List<double> _lastRawFft = const [];
  bool _lastFftComplex = false;

  final FftService _fftService = FftService();
  final AudioOutputService _audioOutputService = AudioOutputService();

  /// Repaint signal for the live visualization layers (one tick per frame).
  final FrameTicker frame = FrameTicker();

  AppSettings _settings;
  late SignalSource _signalSource;
  bool _hasSource = false;
  StreamSubscription<Float64List>? _signalSubscription;
  StreamSubscription<SdrDriverState>? _driverStateSubscription;
  bool _disposed = false;

  /// Down-converter used to pull the tuned channel out of the captured band.
  final ChannelExtractor _channelExtractor = ChannelExtractor();

  /// The band the user has selected on the frequency slider, in absolute Hz.
  /// Null means "the whole captured band".
  double? _tunedStartHz;
  double? _tunedEndHz;

  /// Sample rate the audio chain is currently configured for. Tracked so the
  /// de-emphasis filter is only reconfigured when the channel width changes.
  double _audioChainRate = 0;

  /// The span the hardware is actually delivering, which is not always what
  /// was requested: the RTL2832U resampler caps out at 3.2 MS/s, so asking for
  /// a 20 MHz window silently yields far less. The display must follow this
  /// rather than the requested setting, or the frequency axis lies and every
  /// station smears across it.
  double get rfSpanHz {
    if (_hasSource && _signalSource.isComplex) {
      return _signalSource.sampleRate.toDouble();
    }
    return _settings.rfBandwidth * 1e6;
  }

  /// Centre of the RF band being analysed: the recording's own tuning while
  /// one is replayed, since it was captured wherever the dongle was parked
  /// then, otherwise the configured centre frequency.
  double get centerFrequencyHz {
    final playback = _playback;
    if (playback != null && playback.isComplex) {
      return playback.centerFrequencyHz ?? 0;
    }
    return _settings.centerFrequency * 1e6;
  }

  /// Selects the slice of the captured band to demodulate, in absolute Hz.
  /// Driven by the frequency slider, so tuning a station is a drag rather than
  /// a trip into settings.
  void setTunedBand(double startHz, double endHz) {
    if (_tunedStartHz == startHz && _tunedEndHz == endHz) return;
    _tunedStartHz = startHz;
    _tunedEndHz = endHz;
  }

  /// True when the analysis chain should describe the demodulated audio rather
  /// than the radio band. Requires something to actually demodulate.
  bool get isShowingDemodulated =>
      _hasSource &&
      _signalSource.isComplex &&
      _settings.demodulationMode != DemodulationMode.none &&
      _settings.spectrumView == SpectrumView.demodulated;

  /// Sample rate of whatever the spectrum currently describes: the capture rate
  /// for the RF view, or the tuned channel's rate for the demodulated view.
  double get analysisSampleRate {
    if (!_hasSource) return _settings.rfBandwidth * 1e6;
    final double captureRate = _signalSource.sampleRate.toDouble();
    if (!isShowingDemodulated) return captureRate;
    return captureRate / _channelPlan.decimation;
  }

  /// The frequency span the current spectrum covers, in absolute Hz.
  ///
  /// The RF view spans the tuned centre +/- half the capture rate; the
  /// demodulated view is a real audio spectrum running 0..Nyquist. The two have
  /// completely different axes, so the display has to follow this rather than
  /// assume either one.
  ({double start, double end}) get analysisBandHz {
    if (isShowingDemodulated) {
      return (start: 0, end: analysisSampleRate / 2);
    }
    // A replayed recording is whatever it was captured as, regardless of the
    // source the settings currently select.
    final bool isRfBand = _playback != null
        ? _playback!.isComplex
        : (_hasSource && _signalSource.isComplex) ||
            _settings.signalSource == SignalSourceType.rf;
    if (isRfBand) {
      final double centre = centerFrequencyHz;
      final double half = rfSpanHz / 2;
      return (start: centre - half, end: centre + half);
    }
    // Audio spectrum: 0..Nyquist of the actual capture rate (a nominal
    // placeholder before the source exists).
    return (start: 0, end: _hasSource ? _signalSource.sampleRate / 2 : 22050);
  }

  /// The slice currently being demodulated, if one has been chosen.
  ({double start, double end})? get tunedBandHz {
    final start = _tunedStartHz;
    final end = _tunedEndHz;
    if (start == null || end == null) return null;
    return (start: start, end: end);
  }

  /// How to reach the tuned channel from the current capture.
  ChannelPlan get _channelPlan {
    final start = _tunedStartHz;
    final end = _tunedEndHz;
    if (start == null || end == null) {
      return const ChannelPlan(offsetHz: 0, decimation: 1);
    }
    return planChannel(
      startHz: start,
      endHz: end,
      centerHz: centerFrequencyHz,
      captureRateHz: _signalSource.sampleRate.toDouble(),
    );
  }

  /// Waterfall rows kept on screen. Each is drawn at 1/[maxWaterfallRows] of
  /// the height, so more rows means finer steps as the waterfall falls.
  static const int maxWaterfallRows = 160;
  static const int _maxAudioHistory = 5;

  // ---- Visualization state (read by painters via [frame]) ----
  Float64List currentAudioData = Float64List(0);
  final List<Float64List> audioHistory = [];
  List<double> currentFftData = [];
  final List<List<double>> fftHistory = [];
  ToneInfo? detectedTone;
  double? snr;

  double? _lastI;
  double? _lastQ;

  // Audio-output conditioning (applied to the playback path only, not the
  // visualization): DC removal + FM de-emphasis before rate conversion.
  final DcBlocker _dcBlocker = DcBlocker();
  final Deemphasis _deemphasis =
      Deemphasis(sampleRate: kAudioOutputRate.toDouble());
  final LinearResampler _outputResampler = LinearResampler();

  // ---- Processing inputs set directly by the UI (no notification needed) ----
  double gain = 1.0;
  double sensitivity = 1.0;

  /// Waterfall fall speed (0.1 = slow … 5.0 = fast). Controls how often a new
  /// FFT row is committed to [fftHistory]; the live FFT bar chart still updates
  /// every frame.
  double waterfallSpeed = 1.0;

  /// Running sum of the frames since the last waterfall row, and how many it
  /// holds. Each row is their mean, so a slow waterfall still reflects every
  /// frame in its slot instead of one arbitrary snapshot of it.
  Float64List? _waterfallSum;
  int _waterfallFrameCounter = 0;
  int _waterfallInterval = 1;

  /// Bumped on every committed row, so a renderer can tell how many rows are
  /// new since it last looked and draw only those.
  int waterfallRevision = 0;

  /// Bumped whenever [fftHistory] is cleared, telling a renderer to start over.
  int waterfallEpoch = 0;

  /// How far the slot being accumulated has filled, in (0, 1]. Lets the
  /// waterfall slide smoothly between commits instead of stepping a row.
  double get waterfallProgress =>
      // Raising the speed mid-slot can leave the counter past the new
      // interval until the next frame commits.
      ((_waterfallFrameCounter + 1) / _waterfallInterval).clamp(0.0, 1.0);

  void _clearWaterfall() {
    fftHistory.clear();
    _waterfallSum = null;
    _waterfallFrameCounter = 0;
    waterfallEpoch++;
  }

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  Timer? _demoTimer;
  double _demoPhase = 0.0;

  // Single-flight guard for asynchronous reconfiguration.
  bool _isReconfiguring = false;
  bool _reconfigureQueued = false;

  // ---- Pass-throughs the UI needs ----
  int get sampleRate => _hasSource ? _signalSource.sampleRate : 0;
  bool get isComplex => _hasSource && _signalSource.isComplex;
  List<double>? get peakHoldBuffer => _fftService.peakHoldBuffer;

  /// Updates the settings used for subsequent processing without rebuilding the
  /// source. Call [reconfigure] when source-affecting parameters change.
  void updateSettings(AppSettings settings) {
    // Switching between the RF and demodulated views swaps the spectrum for a
    // completely different signal on a different axis. Accumulated peak-hold
    // and averaging belong to the old one, so carrying them over would paint
    // phantom peaks at meaningless frequencies.
    final bool viewChanged = settings.spectrumView != _settings.spectrumView ||
        settings.demodulationMode != _settings.demodulationMode;
    _settings = settings;
    if (viewChanged) {
      _fftService.clearPeakHold();
      _fftService.clearAveraging();
      detectedTone = null;
      snr = null;
      _clearWaterfall();
      currentFftData = const [];
      _lastRawFft = const [];
    }
  }

  void clearPeakHold() => _fftService.clearPeakHold();

  /// Reconfigures the active signal source. Concurrent invocations are
  /// serialized: if a reconfiguration is already running, one rerun is queued
  /// and executes against whatever `_settings` holds by then — never a stale
  /// snapshot, so a settings change made mid-flight cannot be reverted.
  Future<void> reconfigure({AppSettings? newSettings}) async {
    if (newSettings != null) _settings = newSettings;

    if (_isReconfiguring) {
      _reconfigureQueued = true;
      return;
    }

    _isReconfiguring = true;
    try {
      await _performInitialization();
      while (_reconfigureQueued) {
        _reconfigureQueued = false;
        await _performInitialization();
      }
    } finally {
      _isReconfiguring = false;
    }
  }

  Future<void> _performInitialization() async {
    try {
      final currentSettings = _settings;
      final bool wasCapturing = _isCapturing;

      // A recording holds a single rate and format, so it ends with the
      // source that produced it.
      await stopRecording();
      if (_disposed) return;

      // Gracefully stop and dispose of the current source.
      if (wasCapturing) {
        await _signalSource.stopCapture();
      }
      if (_disposed) return;
      _signalSubscription?.cancel();
      if (_hasSource) _signalSource.dispose();

      _fftService.reset();
      _lastI = null;
      _lastQ = null;

      final playback = _playback;

      // Ensure the native driver is initialized before using the integrated
      // RF source. This is a side effect of selecting that source.
      if (playFile == null &&
          playback == null &&
          currentSettings.signalSource == SignalSourceType.rf &&
          currentSettings.rfSource == RfSourceType.integrated &&
          !NativeSdrDriver().isInitialized) {
        _setupIntegratedDriver();
      }

      _signalSource = playback != null
          ? recordingStore.openPlayback(playback)
          : _sourceFactory(currentSettings, playFile);
      _hasSource = true;

      // Reset audio-output filters and the down-converter for the new stream.
      // The de-emphasis rate is provisional: once demodulation runs it is
      // reconfigured to the tuned channel's rate, which is what actually feeds
      // the filter.
      _dcBlocker.reset();
      _channelExtractor.reset();
      _audioChainRate = _signalSource.sampleRate.toDouble();
      _deemphasis.configure(sampleRate: _audioChainRate);
      _deemphasis.reset();

      // Reusable buffer for decimation.
      Float64List? decimationBuffer;

      _signalSubscription = _signalSource.dataStream.listen((data) {
        if (_disposed) return;
        final recorder = _recorder;
        if (recorder != null) {
          recorder.add(data);
          if (recorder.isFull) unawaited(stopRecording());
        }
        try {
          // Hot path: mutate visualization state directly and repaint only the
          // live layers via [frame].
          final bool isComplex = _signalSource.isComplex;
          final bool useDemod =
              isComplex && _settings.demodulationMode != DemodulationMode.none;

          // Audio path: down-convert the selected slice first, so demodulation
          // hears only the tuned channel instead of the whole captured band.
          // The visualization keeps using the wideband data below.
          Float64List audioInput = data;
          double audioRate = _signalSource.sampleRate.toDouble();
          if (useDemod) {
            final plan = _channelPlan;
            if (!plan.isPassthrough) {
              audioInput = _channelExtractor.process(
                data,
                offsetHz: plan.offsetHz,
                sampleRate: audioRate,
                decimation: plan.decimation,
              );
              audioRate = audioRate / plan.decimation;
            }
            // The audio chain state is rate-dependent, so retune it when the
            // user changes the channel width. The FM demodulator's phase
            // memory also belongs to the old channel plan — carrying it over
            // would compute one phase difference across two different signals
            // and click.
            if (audioRate != _audioChainRate) {
              _audioChainRate = audioRate;
              _deemphasis.configure(sampleRate: audioRate);
              _deemphasis.reset();
              _dcBlocker.reset();
              _outputResampler.reset();
              _lastI = null;
              _lastQ = null;
            }
          }

          final audio = _updateAudioData(audioInput, useDemod: useDemod);

          if (useDemod && _settings.audioOutputEnabled) {
            // Condition the playback signal (on a copy, so the visualization
            // keeps the raw demod output): remove DC, de-emphasize FM, then
            // anti-alias decimate to ~44.1 kHz.
            final audioForOutput = Float64List.fromList(audio);
            _dcBlocker.processInPlace(audioForOutput);
            if (_settings.demodulationMode == DemodulationMode.fm) {
              _deemphasis.processInPlace(audioForOutput);
            }

            // Bring the channel rate down to the output's 44.1 kHz in two
            // steps: an integer averaged decimation (which also anti-aliases),
            // then a fractional resample for the remainder. Integer-only
            // decimation used to leave up to ~10% rate error, which played
            // audio sharp or flat and steadily drifted the output buffer.
            final int decimationFactor =
                (audioRate / kAudioOutputRate).floor().clamp(1, 100);
            Float64List conditioned = audioForOutput;
            if (decimationFactor > 1) {
              decimationBuffer = AudioUtils.decimateAveraged(
                  conditioned, decimationFactor, target: decimationBuffer);
              conditioned = decimationBuffer!;
            }
            final double intermediateRate = audioRate / decimationFactor;
            if (intermediateRate != kAudioOutputRate) {
              _outputResampler.configure(
                  inputRate: intermediateRate,
                  outputRate: kAudioOutputRate.toDouble());
              conditioned = _outputResampler.process(conditioned);
            }
            _audioOutputService.push(conditioned);
          }

          // Which signal the spectrum describes is the user's choice. RF is the
          // default and the map they tune by; the demodulated view instead
          // points the whole analysis chain — tone detection, harmonics, SNR,
          // peak hold — at the recovered audio.
          final bool analyseDemodulated = isShowingDemodulated;
          final bool fftIsComplex = isComplex && !analyseDemodulated;
          _analyseFrame(
            analyseDemodulated ? audio : (isComplex ? data : audio),
            isComplex: fftIsComplex,
          );
        } catch (e) {
          debugPrint("Signal processing error: $e");
        }
      }, onError: (Object e) {
        debugPrint("Signal stream error: $e");
      });

      if (wasCapturing) {
        // Re-start capture if it was active before the reconfiguration.
        final hasPermission = await _signalSource.checkPermission();
        if (_disposed) return;
        if (hasPermission) {
          await _signalSource.startCapture();
        } else {
          _isCapturing = false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Failed to initialize signal source: $e");
    }
  }

  /// Turns a frame into the audio/waveform signal.
  ///
  /// [rawData] is the down-converted channel when [useDemod] is set, not the
  /// raw capture — demodulating the full band would mix every station at once.
  Float64List _updateAudioData(Float64List rawData, {required bool useDemod}) {
    Float64List processedAudio;
    final gain = this.gain;

    if (useDemod) {
      final int numPairs = rawData.length ~/ 2;
      processedAudio = Float64List(numPairs);

      if (_settings.demodulationMode == DemodulationMode.am) {
        // AM demodulation: magnitude (envelope detection).
        for (int i = 0; i < numPairs; i++) {
          final I = rawData[i * 2];
          final Q = rawData[i * 2 + 1];
          processedAudio[i] = math.sqrt(I * I + Q * Q) * gain;
        }
      } else {
        // FM demodulation: quadrature demodulation (phase difference).
        for (int i = 0; i < numPairs; i++) {
          final I = rawData[i * 2];
          final Q = rawData[i * 2 + 1];

          if (_lastI != null && _lastQ != null) {
            processedAudio[i] = math.atan2(Q * _lastI! - I * _lastQ!, I * _lastI! + Q * _lastQ!) * gain;
          } else {
            processedAudio[i] = 0;
          }
          _lastI = I;
          _lastQ = Q;
        }
      }
    } else {
      processedAudio = Float64List(rawData.length);
      for (int i = 0; i < rawData.length; i++) {
        processedAudio[i] = rawData[i] * gain;
      }
    }

    if (currentAudioData.isNotEmpty) {
      audioHistory.insert(0, currentAudioData);
      if (audioHistory.length > _maxAudioHistory) audioHistory.removeLast();
    }
    currentAudioData = processedAudio;
    return processedAudio;
  }

  void _processFftFrame(List<double> rawFft, {required bool isComplex}) {
    if (rawFft.isEmpty) return;
    _lastRawFft = rawFft;
    _lastFftComplex = isComplex;

    final double sensitivity = this.sensitivity;

    final adjustedFft = List<double>.filled(rawFft.length, 0);
    for (int i = 0; i < rawFft.length; i++) {
      adjustedFft[i] = rawFft[i] * sensitivity;
    }

    currentFftData = adjustedFft;
    // Tone detection is only meaningful for real-valued signals, and needs
    // the rate of the signal actually analysed — in the demodulated view that
    // is the tuned channel's rate, not the capture rate.
    detectedTone = isComplex
        ? null
        : _fftService.detectPrimaryTone(adjustedFft, analysisSampleRate.round());
    snr = _fftService.calculateSNR(adjustedFft);

    // Commit a waterfall row every Nth frame, where N is set by the waterfall
    // speed dial (higher speed -> more rows -> faster fall). The row averages
    // all N frames: sampling just one of them made slow speeds flicker with
    // noise and drop anything shorter than a slot.
    Float64List? sum = _waterfallSum;
    if (sum == null || sum.length != adjustedFft.length) {
      // A window-size or real/complex change: bins no longer line up.
      sum = _waterfallSum = Float64List(adjustedFft.length);
      _waterfallFrameCounter = 0;
    }
    for (int i = 0; i < sum.length; i++) {
      sum[i] += adjustedFft[i];
    }
    _waterfallFrameCounter++;

    final int interval = (4.0 / waterfallSpeed).round().clamp(1, 50);
    _waterfallInterval = interval;
    if (_waterfallFrameCounter >= interval) {
      final int count = _waterfallFrameCounter;
      // Unboxed rows: a List<double> would box each of up to 4096 bins, in
      // every one of the kept rows.
      final row = Float64List(sum.length);
      for (int i = 0; i < row.length; i++) {
        row[i] = sum[i] / count;
      }
      fftHistory.insert(0, row);
      waterfallRevision++;
      if (fftHistory.length > maxWaterfallRows) {
        fftHistory.removeLast();
      }
      sum.fillRange(0, sum.length, 0);
      _waterfallFrameCounter = 0;
    }
  }

  /// Shared tail of the analysis chain: FFT the given frame with the current
  /// settings, update the visualization state, and repaint the live layers.
  void _analyseFrame(Float64List samples, {required bool isComplex}) {
    final fft = _fftService.processSignalData(
      samples,
      windowSize: _settings.fftWindowSize,
      windowType: _settings.fftWindowType,
      isComplex: isComplex,
      peakHoldEnabled: _settings.peakHoldEnabled,
      averagingMode: _settings.fftAveragingMode,
      averagingCount: _settings.fftAveragingCount,
    );
    _processFftFrame(fft, isComplex: isComplex);
    frame.tick();
  }

  void _startDemoData() {
    _demoTimer?.cancel();
    _demoPhase = 0.0;
    // 440Hz fundamental (A4) at a 44.1 kHz sample rate.
    const fundamental = 440.0;
    const sampleRate = 44100.0;
    const phaseStep = 2 * math.pi * fundamental / sampleRate;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final samples = Float64List(512);

      // Accumulate phase continuously across frames (kept bounded to preserve
      // floating-point precision).
      for (var i = 0; i < 512; i++) {
        samples[i] = 0.6 * math.sin(_demoPhase) +
            0.3 * math.sin(2 * _demoPhase) +
            0.1 * math.sin(3 * _demoPhase);
        _demoPhase += phaseStep;
        if (_demoPhase > 2 * math.pi) _demoPhase -= 2 * math.pi;
      }
      if (_disposed) return;
      _updateAudioData(samples, useDemod: false);
      _analyseFrame(samples, isComplex: false);
    });
  }

  /// Toggles capture on/off. Notifies listeners when [isCapturing] changes.
  Future<void> toggleCapture() async {
    // The source may not exist if its factory threw during initialization.
    if (!isDemoMode && !_hasSource) return;
    try {
      if (_isCapturing) {
        await stopRecording();
        if (isDemoMode) {
          _demoTimer?.cancel();
          _demoTimer = null;
        } else {
          await _signalSource.stopCapture();
        }
        if (_disposed) return;
        _isCapturing = false;
        currentAudioData = Float64List(0);
        audioHistory.clear();
        currentFftData = [];
        _clearWaterfall();
        _lastRawFft = const [];
        detectedTone = null;
        snr = null;
        _lastI = null;
        _lastQ = null;
        _fftService.clearPeakHold();
        _fftService.clearAveraging();
        frame.tick();
        notifyListeners();
      } else {
        if (isDemoMode) {
          _startDemoData();
          _audioOutputService.resume();
          _isCapturing = true;
          notifyListeners();
        } else {
          final hasPermission = await _signalSource.checkPermission();
          if (_disposed) return;
          if (hasPermission) {
            await _signalSource.startCapture();
            if (_disposed) return;
            _audioOutputService.resume();
            _isCapturing = true;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint("Capture error: $e");
    }
  }

  /// True when the integrated USB source is the one currently in use.
  bool get _usingIntegratedSource =>
      playFile == null &&
      !isDemoMode &&
      _playback == null &&
      _settings.signalSource == SignalSourceType.rf &&
      _settings.rfSource == RfSourceType.integrated;

  /// Drives the driver lifecycle off hot-plug events so plugging a dongle in
  /// is enough to get it set up — no settings round-trip required.
  void _onDriverStateChanged(SdrDriverState state) {
    if (_disposed) return;

    if (_usingIntegratedSource) {
      switch (state) {
        case SdrDriverState.ready:
          // Attached and permitted but not open yet: bring it up.
          unawaited(_setupIntegratedDriver());
          break;
        case SdrDriverState.open:
          // Rebind the source so it streams from the now-open dongle.
          unawaited(reconfigure());
          break;
        case SdrDriverState.noDevice:
        case SdrDriverState.error:
          // Unplugged (or the stream died) mid-capture: stop cleanly instead
          // of leaving a dead source running.
          if (_isCapturing) unawaited(toggleCapture());
          break;
        case SdrDriverState.needsPermission:
        case SdrDriverState.unsupported:
          break;
      }
    }

    // The settings sheet renders the driver state, so refresh either way.
    notifyListeners();
  }

  Future<void> _setupIntegratedDriver() async {
    // reconfigure() runs from the resulting SdrDriverState.open event, so the
    // source is rebound exactly once regardless of who triggered the open.
    final success = await NativeSdrDriver().initialize(
      sampleRate: clampRtlSampleRate((_settings.rfBandwidth * 1e6).toInt()),
      frequency: (_settings.centerFrequency * 1e6).toInt(),
      ppm: _settings.ppmCorrection.round(),
    );
    if (!success && !_disposed) notifyListeners();
  }

  /// Requests USB access for an attached dongle, then opens it. Surfaced as
  /// the settings sheet's **Connect** action, so a driver that needs setup is
  /// something the user can act on rather than just a status label.
  Future<void> setupIntegratedDriver() async {
    final driver = NativeSdrDriver();
    await driver.refreshDevices();
    if (_disposed) return;
    if (driver.state == SdrDriverState.needsPermission) {
      if (!await driver.requestPermission()) return;
      if (_disposed) return;
    }
    await _setupIntegratedDriver();
  }

  // ---- Recording, playback and export ----

  bool get isRecording => _recorder != null;
  Duration get recordingDuration => _recorder?.duration ?? Duration.zero;
  int get recordingBytes => _recorder?.bytesWritten ?? 0;

  /// The recording replayed in place of the live source, if any.
  RecordingInfo? get playbackRecording => _playback;

  /// Recording captures a live source; replaying a file or the synthesized
  /// demo tone into a new file would only duplicate it.
  bool get canRecord =>
      recordingStore.isSupported &&
      _isCapturing &&
      _hasSource &&
      !isDemoMode &&
      _playback == null;

  /// Starts writing the raw source stream to the library: WAV for audio,
  /// SigMF for I/Q. Returns false when recording is not possible right now.
  Future<bool> startRecording() async {
    if (!canRecord || _recorder != null) return false;
    try {
      final sink = await recordingStore.startRecording(
        sampleRate: _signalSource.sampleRate,
        isComplex: _signalSource.isComplex,
        centerFrequencyHz:
            _signalSource.isComplex ? centerFrequencyHz : null,
      );
      if (_disposed || !canRecord) {
        await sink.close();
        return false;
      }
      _recorder = sink;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      return false;
    }
  }

  /// Finalizes the current recording, if any, and returns its entry.
  Future<RecordingInfo?> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    // Detach first, so frames arriving during the close are not written.
    _recorder = null;
    if (!_disposed) notifyListeners();
    try {
      return await recorder.close();
    } catch (e) {
      debugPrint('Failed to finalize recording: $e');
      return null;
    }
  }

  /// Replays [recording] through the full analysis chain in place of the live
  /// source, starting capture if it was stopped.
  Future<void> startPlayback(RecordingInfo recording) async {
    if (!recording.isPlayable) return;
    _playback = recording;
    await reconfigure();
    if (_disposed) return;
    if (!_isCapturing) await toggleCapture();
    notifyListeners();
  }

  /// Returns to the live source, idle.
  Future<void> stopPlayback() async {
    if (_playback == null) return;
    if (_isCapturing) await toggleCapture();
    _playback = null;
    await reconfigure();
    if (!_disposed) notifyListeners();
  }

  /// Whether a spectrum has been analysed, i.e. whether [spectrumCsv] has
  /// anything to export.
  bool get hasSpectrum => _lastRawFft.isNotEmpty;

  /// The last analysed spectrum as CSV, or null before any frame has been
  /// analysed. Magnitudes are exported without the sensitivity display scale.
  String? spectrumCsv() {
    final fft = List<double>.of(_lastRawFft);
    if (fft.isEmpty) return null;
    final band = analysisBandHz;
    final peak = _settings.peakHoldEnabled ? _fftService.peakHoldBuffer : null;
    return buildSpectrumCsv(
      magnitudes: fft,
      peakHold: peak == null ? null : List<double>.of(peak),
      bandStartHz: band.start,
      bandEndHz: band.end,
      isComplex: _lastFftComplex,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) unawaited(recorder.close());
    _signalSubscription?.cancel();
    _driverStateSubscription?.cancel();
    _demoTimer?.cancel();
    frame.dispose();
    if (_hasSource) _signalSource.dispose();
    _audioOutputService.dispose();
    super.dispose();
  }
}
