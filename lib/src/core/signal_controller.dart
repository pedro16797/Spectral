import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../audio/audio_capture_service.dart';
import '../audio/audio_output_service.dart';
import '../rf/rf_capture_service.dart';
import '../rf/rtl_tcp_capture_service.dart'
    if (dart.library.html) '../rf/rtl_tcp_capture_service_stub.dart';
import '../rf/integrated_rf_capture_service.dart';
import '../rf/native_sdr_driver.dart';
import '../rf/rtl2832u.dart';
import '../utils/audio_utils.dart';
import '../utils/mock_file_signal_source.dart';
import 'audio_filters.dart';
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
        return RfCaptureService(
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
  })  : _settings = settings,
        _sourceFactory = sourceFactory ?? defaultSignalSourceFactory {
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

  static const int _maxHistory = 40;
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
  // visualization): DC removal + FM de-emphasis before decimation.
  final DcBlocker _dcBlocker = DcBlocker();
  final Deemphasis _deemphasis = Deemphasis(sampleRate: 44100);

  // ---- Processing inputs set directly by the UI (no notification needed) ----
  double gain = 1.0;
  double sensitivity = 1.0;

  /// Waterfall fall speed (0.1 = slow … 5.0 = fast). Controls how often a new
  /// FFT row is committed to [fftHistory]; the live FFT bar chart still updates
  /// every frame.
  double waterfallSpeed = 1.0;
  int _waterfallFrameCounter = 0;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  Timer? _demoTimer;
  double _demoPhase = 0.0;

  // Single-flight guard for asynchronous reconfiguration.
  bool _isReconfiguring = false;
  bool _reconfigureQueued = false;
  AppSettings? _queuedSettings;

  // ---- Pass-throughs the UI needs ----
  int get sampleRate => _signalSource.sampleRate;
  bool get isComplex => _signalSource.isComplex;
  List<double>? get peakHoldBuffer => _fftService.peakHoldBuffer;

  /// Updates the settings used for subsequent processing without rebuilding the
  /// source. Call [reconfigure] when source-affecting parameters change.
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  void clearPeakHold() => _fftService.clearPeakHold();

  /// Reconfigures the active signal source. Concurrent invocations are
  /// serialized: if a reconfiguration is already running, the latest requested
  /// settings are queued and applied once the in-flight one completes.
  Future<void> reconfigure({AppSettings? newSettings}) async {
    // Always reflect the latest requested settings in `_settings` immediately.
    // The queue below relies on this: when a queued reconfigure carries no new
    // settings, falling back to the current `_settings` is correct because the
    // most recent non-null settings were already stored here.
    if (newSettings != null) _settings = newSettings;

    if (_isReconfiguring) {
      _reconfigureQueued = true;
      _queuedSettings = newSettings;
      return;
    }

    _isReconfiguring = true;
    try {
      await _performInitialization();
      while (_reconfigureQueued) {
        _reconfigureQueued = false;
        final queued = _queuedSettings;
        _queuedSettings = null;
        if (queued != null) _settings = queued;
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

      // Ensure the native driver is initialized before using the integrated
      // RF source. This is a side effect of selecting that source.
      if (playFile == null &&
          currentSettings.signalSource == SignalSourceType.rf &&
          currentSettings.rfSource == RfSourceType.integrated &&
          !NativeSdrDriver().isInitialized) {
        _setupIntegratedDriver();
      }

      _signalSource = _sourceFactory(currentSettings, playFile);
      _hasSource = true;

      // Reset audio-output filters for the new stream and match the FM
      // de-emphasis time constant to the source's sample rate.
      _dcBlocker.reset();
      _deemphasis.configure(sampleRate: _signalSource.sampleRate.toDouble());
      _deemphasis.reset();

      // Reusable buffer for decimation.
      Float64List? decimationBuffer;

      _signalSubscription = _signalSource.dataStream.listen((data) {
        if (_disposed) return;
        try {
          // Hot path: mutate visualization state directly and repaint only the
          // live layers via [frame].
          final audio = _updateAudioData(data);
          final bool useDemod =
              _signalSource.isComplex && _settings.demodulationMode != DemodulationMode.none;

          if (useDemod && _settings.audioOutputEnabled) {
            // Condition the playback signal (on a copy, so the visualization
            // keeps the raw demod output): remove DC, de-emphasize FM, then
            // anti-alias decimate to ~44.1 kHz.
            final audioForOutput = Float64List.fromList(audio);
            _dcBlocker.processInPlace(audioForOutput);
            if (_settings.demodulationMode == DemodulationMode.fm) {
              _deemphasis.processInPlace(audioForOutput);
            }

            final int decimationFactor = (_signalSource.sampleRate / 44100).round().clamp(1, 100);
            if (decimationFactor > 1) {
              decimationBuffer =
                  AudioUtils.decimateAveraged(audioForOutput, decimationFactor, target: decimationBuffer);
              _audioOutputService.push(decimationBuffer!);
            } else {
              _audioOutputService.push(audioForOutput);
            }
          }

          final fft = _fftService.processSignalData(
            useDemod ? audio : data,
            windowSize: _settings.fftWindowSize,
            windowType: _settings.fftWindowType,
            isComplex: useDemod ? false : _signalSource.isComplex,
            peakHoldEnabled: _settings.peakHoldEnabled,
            averagingMode: _settings.fftAveragingMode,
            averagingCount: _settings.fftAveragingCount,
          );
          _processFftFrame(fft, isComplex: useDemod ? false : _signalSource.isComplex);
          frame.tick();
        } catch (e) {
          debugPrint("Signal processing error: $e");
        }
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

  Float64List _updateAudioData(Float64List rawData) {
    Float64List processedAudio;
    final gain = this.gain;
    final bool useDemod =
        _signalSource.isComplex && _settings.demodulationMode != DemodulationMode.none;

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

    final double sensitivity = this.sensitivity;

    final adjustedFft = List<double>.filled(rawFft.length, 0);
    for (int i = 0; i < rawFft.length; i++) {
      adjustedFft[i] = rawFft[i] * sensitivity;
    }

    currentFftData = adjustedFft;
    // Tone detection is only meaningful for real-valued signals.
    detectedTone = isComplex ? null : _fftService.detectPrimaryTone(adjustedFft, _signalSource.sampleRate);
    snr = _fftService.calculateSNR(adjustedFft);

    if (adjustedFft.isNotEmpty) {
      // Commit a waterfall row only every Nth frame, where N is set by the
      // waterfall speed dial (higher speed -> more rows -> faster fall).
      _waterfallFrameCounter++;
      final int interval = (4.0 / waterfallSpeed).round().clamp(1, 50);
      if (_waterfallFrameCounter >= interval) {
        _waterfallFrameCounter = 0;
        fftHistory.insert(0, adjustedFft);
        if (fftHistory.length > _maxHistory) {
          fftHistory.removeLast();
        }
      }
    }
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
      _updateAudioData(samples);

      final fft = _fftService.processSignalData(
        samples,
        windowSize: _settings.fftWindowSize,
        windowType: _settings.fftWindowType,
        isComplex: false,
        peakHoldEnabled: _settings.peakHoldEnabled,
        averagingMode: _settings.fftAveragingMode,
        averagingCount: _settings.fftAveragingCount,
      );
      _processFftFrame(fft, isComplex: false);
      frame.tick();
    });
  }

  /// Toggles capture on/off. Notifies listeners when [isCapturing] changes.
  Future<void> toggleCapture() async {
    try {
      if (_isCapturing) {
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
        fftHistory.clear();
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

  @override
  void dispose() {
    _disposed = true;
    _signalSubscription?.cancel();
    _driverStateSubscription?.cancel();
    _demoTimer?.cancel();
    frame.dispose();
    _signalSource.dispose();
    _audioOutputService.dispose();
    super.dispose();
  }
}
