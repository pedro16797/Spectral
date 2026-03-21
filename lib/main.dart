import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/audio/audio_capture_service.dart';
import 'src/audio/audio_output_service.dart';
import 'src/rf/rf_capture_service.dart';
import 'src/rf/rtl_tcp_capture_service.dart';
import 'src/rf/integrated_rf_capture_service.dart';
import 'src/rf/native_sdr_driver.dart';
import 'src/rf/native_sdr_driver_ffi.dart' if (dart.library.html) 'src/rf/native_sdr_driver_web.dart';
import 'src/core/signal_source.dart';
import 'src/core/fft_service.dart';
import 'src/core/settings_model.dart';
import 'src/ui/waveform_painter.dart';
import 'src/ui/fft_bar_chart_painter.dart';
import 'src/ui/waterfall_painter.dart';
import 'src/ui/radio_dial_focus_slider.dart';
import 'src/ui/settings_view.dart';
import 'src/utils/localization_helper.dart';
import 'src/services/settings_service.dart';
import 'src/utils/mock_file_signal_source.dart';
import 'src/utils/frequency_formatter.dart';
import 'src/utils/audio_utils.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Support state injection via base64 encoded settings in URL (headless environments)
    AppSettings settings;
    final String? b64 = Uri.base.queryParameters['settings_b64'];
    if (b64 != null) {
      try {
        final decoded = utf8.decode(base64Decode(b64));
        settings = AppSettings.fromMap(json.decode(decoded));
      } catch (e) {
        debugPrint("Error decoding settings_b64: $e");
        settings = await SettingsService.loadSettings();
      }
    } else {
      settings = await SettingsService.loadSettings();
    }

    await LocalizationHelper.load(settings.language);

    // Initialize the SDR driver based on the current platform
    // This is handled via conditional imports above
    NativeSdrDriver().setDelegate(NativeSdrDriverDelegate());

    runApp(SpectralApp(initialSettings: settings));
  } catch (e) {
    debugPrint("Startup error: $e");
    // Minimal fallback app if initialization fails
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Failed to start Spectral: $e"),
        ),
      ),
    ));
  }
}

class SpectralApp extends StatefulWidget {
  final AppSettings initialSettings;
  const SpectralApp({super.key, required this.initialSettings});

  @override
  State<SpectralApp> createState() => _SpectralAppState();
}

class _SpectralAppState extends State<SpectralApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    SettingsService.saveSettings(newSettings);
  }

  Color _getAccentColor() {
    switch (_settings.theme) {
      case AppTheme.frost:
        return const Color(0xFF007AFF);
      case AppTheme.magma:
        return Colors.orangeAccent;
      case AppTheme.gray:
        return Colors.white;
      case AppTheme.emerald:
        return const Color(0xFF00C853);
      case AppTheme.rainbow:
        return Colors.purpleAccent;
    }
  }

  Color _getBackgroundColor() {
    switch (_settings.theme) {
      case AppTheme.frost:
        return const Color(0xFF001A33);
      case AppTheme.magma:
        return const Color(0xFF330D00);
      case AppTheme.gray:
        return const Color(0xFF1A1A1A);
      case AppTheme.emerald:
        return const Color(0xFF001A00);
      case AppTheme.rainbow:
        return const Color(0xFF100010);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor();
    final backgroundColor = _getBackgroundColor();

    return MaterialApp(
      title: LocalizationHelper.get('app.name'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: accentColor,
          surface: const Color(0xFF1C1C1E),
        ),
        useMaterial3: true,
      ),
      home: SpectralHomePage(
        settings: _settings,
        onSettingsChanged: _updateSettings,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class SpectralHomePage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Color backgroundColor;

  const SpectralHomePage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.backgroundColor,
  });

  @override
  State<SpectralHomePage> createState() => _SpectralHomePageState();
}

class DialArcPainter extends CustomPainter {
  final double value;
  final bool isLeft;
  final Color color;
  DialArcPainter({required this.value, required this.isLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 12; // Avoid clipping at widget bounds

    const totalVisibleSweep = 1.2;
    final progressSweep = (value / 5.0) * totalVisibleSweep;

    final basePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;

    if (isLeft) {
      // Left dial: Visible is the right side of the circle.
      // Fill bottom to top (counter-clockwise)
      const startAngle = totalVisibleSweep / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        -totalVisibleSweep,
        false,
        basePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        -progressSweep,
        false,
        progressPaint,
      );
    } else {
      // Right dial: Visible is the left side of the circle.
      // Fill bottom to top (clockwise)
      const startAngle = math.pi - (totalVisibleSweep / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        totalVisibleSweep,
        false,
        basePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DialArcPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class _SpectralHomePageState extends State<SpectralHomePage> with TickerProviderStateMixin {
  static const double _kLargeDialSizeScale = 0.7;
  static const double _kLargeDialOffsetScale = 0.8;

  late SignalSource _signalSource;
  final FftService _fftService = FftService();
  final AudioOutputService _audioOutputService = AudioOutputService();
  StreamSubscription<Float64List>? _signalSubscription;
  Float64List _currentAudioData = Float64List(0);
  final List<Float64List> _audioHistory = [];
  List<double> _currentFftData = [];
  final List<List<double>> _fftHistory = [];
  static const int _maxHistory = 40;
  ToneInfo? _detectedTone;
  double? _snr;
  double? _lastI;
  double? _lastQ;
  final List<double> _markers = [];
  bool _isCapturing = false;
  bool _isDemoMode = false;
  String? _playFile;
  Timer? _demoTimer;
  bool _waterfallFocusMode = false;

  double _gain = 1.0;
  double _sensitivity = 1.0;
  RangeValues _freqRange = const RangeValues(0, 22050);

  bool _gainPersistent = false;
  bool _sensPersistent = false;
  bool _isDraggingGain = false;
  bool _isDraggingSens = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isDemoMode = Uri.base.queryParameters['demo'] == 'true';
    _playFile = Uri.base.queryParameters['play_file'];

    // Initial dummy source to avoid late initialization error
    _signalSource = AudioCaptureService();
    _audioOutputService.init();
    _initializeSignalSource();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _initializeSignalSource({AppSettings? newSettings}) async {
    try {
      final currentSettings = newSettings ?? widget.settings;
      final bool wasCapturing = _isCapturing;

      // Gracefully stop and dispose of the current source
      if (wasCapturing) {
        await _signalSource.stopCapture();
      }
      _signalSubscription?.cancel();
      _signalSource.dispose();

      _fftService.reset();
      _lastI = null;
      _lastQ = null;

      if (_playFile != null) {
        _signalSource = MockFileSignalSource(
          assetPath: _playFile!,
          isComplex: currentSettings.signalSource == SignalSourceType.rf,
          sampleRate: currentSettings.signalSource == SignalSourceType.rf
              ? (currentSettings.rfBandwidth * 1e6).toInt()
              : 44100,
        );
      } else if (currentSettings.signalSource == SignalSourceType.rf) {
        if (currentSettings.rfSource == RfSourceType.rtlTcp) {
          _signalSource = RtlTcpCaptureService(
            host: currentSettings.rtlTcpHost,
            port: currentSettings.rtlTcpPort,
            sampleRate: (currentSettings.rfBandwidth * 1e6).toInt(),
            frequency: (currentSettings.centerFrequency * 1e6).toInt(),
          );
        } else if (currentSettings.rfSource == RfSourceType.integrated) {
          // Trigger driver setup if needed
          if (!NativeSdrDriver().isInitialized) {
            _setupIntegratedDriver();
          }
          _signalSource = IntegratedRfCaptureService(
            centerFrequency: currentSettings.centerFrequency * 1e6,
            bandwidth: currentSettings.rfBandwidth * 1e6,
            ppmCorrection: currentSettings.ppmCorrection,
          );
        } else {
          _signalSource = RfCaptureService(
            centerFrequency: currentSettings.centerFrequency * 1e6,
            bandwidth: currentSettings.rfBandwidth * 1e6,
          );
        }
      } else {
        _signalSource = AudioCaptureService();
      }

      if (currentSettings.signalSource == SignalSourceType.rf) {
        _freqRange = RangeValues(
          (currentSettings.centerFrequency - currentSettings.rfBandwidth / 2) * 1e6,
          (currentSettings.centerFrequency + currentSettings.rfBandwidth / 2) * 1e6,
        );
      } else {
        _freqRange = const RangeValues(0, 22050);
      }

      // Reusable buffers for decimation and processing
      Float64List? decimationBuffer;

      _signalSubscription = _signalSource.dataStream.listen((data) {
        if (!mounted) return;

        try {
          setState(() {
            final audio = _updateAudioData(data);
            final bool useDemod =
                _signalSource.isComplex && widget.settings.demodulationMode != DemodulationMode.none;

            if (useDemod && widget.settings.audioOutputEnabled) {
              // Decimation: Downsampling of SDR stream to ~44.1 kHz for audio output.
              final int decimationFactor = (_signalSource.sampleRate / 44100).round().clamp(1, 100);
              if (decimationFactor > 1) {
                decimationBuffer = AudioUtils.decimate(audio, decimationFactor, target: decimationBuffer);
                _audioOutputService.push(decimationBuffer!);
              } else {
                _audioOutputService.push(audio);
              }
            }

            final fft = _fftService.processSignalData(
              useDemod ? audio : data,
              windowSize: widget.settings.fftWindowSize,
              windowType: widget.settings.fftWindowType,
              isComplex: useDemod ? false : _signalSource.isComplex,
              peakHoldEnabled: widget.settings.peakHoldEnabled,
              averagingMode: widget.settings.fftAveragingMode,
              averagingCount: widget.settings.fftAveragingCount,
            );
            _processFftFrame(fft, isComplex: useDemod ? false : _signalSource.isComplex);
          });
        } catch (e) {
          debugPrint("Signal processing error: $e");
        }
      });

      if (wasCapturing) {
        // Re-start capture if it was active
        final hasPermission = await _signalSource.checkPermission();
        if (hasPermission) {
          await _signalSource.startCapture();
        } else {
          setState(() {
            _isCapturing = false;
            _pulseController.stop();
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to initialize signal source: $e");
    }
  }

  Float64List _updateAudioData(Float64List rawData) {
    Float64List processedAudio;
    final gain = _gain;
    final bool useDemod = _signalSource.isComplex && widget.settings.demodulationMode != DemodulationMode.none;

    if (useDemod) {
      final int numPairs = rawData.length ~/ 2;
      processedAudio = Float64List(numPairs);

      if (widget.settings.demodulationMode == DemodulationMode.am) {
        // AM Demodulation: Magnitude (Envelope detection)
        for (int i = 0; i < numPairs; i++) {
          final I = rawData[i * 2];
          final Q = rawData[i * 2 + 1];
          processedAudio[i] = math.sqrt(I * I + Q * Q) * gain;
        }
      } else {
        // FM Demodulation: Quadrature demodulation (phase difference)
        for (int i = 0; i < numPairs; i++) {
          final I = rawData[i * 2];
          final Q = rawData[i * 2 + 1];

          if (_lastI != null && _lastQ != null) {
            // Standard FM quadrature demodulation (cross product and dot product)
            // atan2(Qn*In-1 - In*Qn-1, In*In-1 + Qn*Qn-1)
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

    if (_currentAudioData.isNotEmpty) {
      _audioHistory.insert(0, _currentAudioData);
      if (_audioHistory.length > 5) _audioHistory.removeLast();
    }
    _currentAudioData = processedAudio;
    return processedAudio;
  }

  void _processFftFrame(List<double> rawFft, {required bool isComplex}) {
    if (rawFft.isEmpty) return;

    final double sensitivity = _sensitivity;

    List<double> adjustedFft;
    adjustedFft = List<double>.filled(rawFft.length, 0);
    for (int i = 0; i < rawFft.length; i++) {
      adjustedFft[i] = rawFft[i] * sensitivity;
    }

    _currentFftData = adjustedFft;
    // Tone detection is only meaningful for real-valued signals (audio or demodulated RF)
    _detectedTone = isComplex ? null : _fftService.detectPrimaryTone(adjustedFft, _signalSource.sampleRate);
    _snr = _fftService.calculateSNR(adjustedFft);

    if (adjustedFft.isNotEmpty) {
      _fftHistory.insert(0, adjustedFft);
      if (_fftHistory.length > _maxHistory) {
        _fftHistory.removeLast();
      }
    }
  }

  void _startDemoData() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final samples = Float64List(512);
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      // 440Hz Fundamental (A4)
      const fundamental = 440.0;
      final phase = now * 2 * math.pi * fundamental;

      for (var i = 0; i < 512; i++) {
        final t = i / 44100.0;
        samples[i] = (
          0.6 * math.sin(phase + t * 2 * math.pi * fundamental) + // Fundamental
          0.3 * math.sin(2 * (phase + t * 2 * math.pi * fundamental)) + // 2nd Harmonic
          0.1 * math.sin(3 * (phase + t * 2 * math.pi * fundamental))    // 3rd Harmonic
        );
      }
      if (mounted) {
        setState(() {
          _updateAudioData(samples);

          final fft = _fftService.processSignalData(
            samples,
            windowSize: widget.settings.fftWindowSize,
            windowType: widget.settings.fftWindowType,
            isComplex: false,
            peakHoldEnabled: widget.settings.peakHoldEnabled,
            averagingMode: widget.settings.fftAveragingMode,
            averagingCount: widget.settings.fftAveragingCount,
          );
          _processFftFrame(fft, isComplex: false);
        });
      }
    });
  }

  Future<void> _toggleCapture() async {
    try {
      HapticFeedback.mediumImpact();
      if (_isCapturing) {
        if (_isDemoMode) {
          _demoTimer?.cancel();
          _demoTimer = null;
        } else {
          await _signalSource.stopCapture();
        }
        _pulseController.stop();
        setState(() {
          _isCapturing = false;
          _currentAudioData = Float64List(0);
          _audioHistory.clear();
          _currentFftData = [];
          _fftHistory.clear();
          _snr = null;
          _lastI = null;
          _lastQ = null;
          _fftService.clearPeakHold();
          _fftService.clearAveraging();
        });
      } else {
        if (_isDemoMode) {
          _startDemoData();
          _audioOutputService.resume();
          _pulseController.repeat(reverse: true);
          setState(() => _isCapturing = true);
        } else {
          final hasPermission = await _signalSource.checkPermission();
          if (hasPermission) {
            await _signalSource.startCapture();
            _audioOutputService.resume();
            _pulseController.repeat(reverse: true);
            setState(() => _isCapturing = true);
          }
        }
      }
    } catch (e) {
      debugPrint("Capture error: $e");
    }
  }

  Future<void> _setupIntegratedDriver() async {
    final success = await NativeSdrDriver().initialize();
    if (success && mounted) {
      setState(() {
        // Re-initialize source now that driver is ready
        _initializeSignalSource();
      });
    }
  }

  void _showSettings() {
    try {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Settings",
        pageBuilder: (context, _, __) => SettingsView(
          settings: widget.settings,
          onSettingsChanged: (newSettings) {
            final oldSource = widget.settings.signalSource;
            final oldFreq = widget.settings.centerFrequency;
            final oldBw = widget.settings.rfBandwidth;
            final oldPpm = widget.settings.ppmCorrection;

            widget.onSettingsChanged(newSettings);

            if (oldSource != newSettings.signalSource ||
                oldFreq != newSettings.centerFrequency ||
                oldBw != newSettings.rfBandwidth ||
                oldPpm != newSettings.ppmCorrection ||
                widget.settings.rfSource != newSettings.rfSource ||
                widget.settings.rtlTcpHost != newSettings.rtlTcpHost ||
                widget.settings.rtlTcpPort != newSettings.rtlTcpPort) {
              _initializeSignalSource(newSettings: newSettings);
            }

            if (!newSettings.peakHoldEnabled) {
              _fftService.clearPeakHold();
            }
          },
        ),
      );
    } catch (e) {
      debugPrint("Error showing settings: $e");
    }
  }

  void _handleFftTap(Offset localOffset, Size size) {
    final freq = _screenOffsetToFreq(localOffset.dx, size.width);
    setState(() {
      // Find and remove if close (within a small frequency epsilon or visual range)
      final double epsilon = (_freqRange.end - _freqRange.start) * 0.02;
      int existingIndex = -1;
      for (int i = 0; i < _markers.length; i++) {
        if ((_markers[i] - freq).abs() < epsilon) {
          existingIndex = i;
          break;
        }
      }

      if (existingIndex != -1) {
        _markers.removeAt(existingIndex);
      } else {
        if (_markers.length >= 3) _markers.removeAt(0);
        _markers.add(freq);
        HapticFeedback.selectionClick();
      }
    });
  }

  double _screenOffsetToFreq(double x, double width) {
    double t = x / width;
    if (widget.settings.frequencySkew != 1.0) {
      t = math.pow(t, widget.settings.frequencySkew).toDouble();
    }
    return _freqRange.start + (_freqRange.end - _freqRange.start) * t;
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _demoTimer?.cancel();
    _pulseController.dispose();
    _signalSource.dispose();
    _audioOutputService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.secondary;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final useTabletLayout = isTablet && isLandscape;

    return Scaffold(
      body: Stack(
        children: [
          // Background Liquid Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.6),
                  radius: 1.5,
                  colors: [widget.backgroundColor, Colors.black],
                ),
              ),
            ),
          ),

          // Waterfall Background
          Positioned.fill(
            child: Opacity(
              opacity: _waterfallFocusMode ? 1.0 : 0.4,
              child: CustomPaint(
                size: Size.infinite,
                painter: WaterfallPainter(
                  fftHistory: _fftHistory,
                  minFreq: _freqRange.start,
                  maxFreq: _freqRange.end,
                  sampleRate: _signalSource.sampleRate,
                  theme: widget.settings.theme,
                  frequencySkew: widget.settings.frequencySkew,
                ),
              ),
            ),
          ),

          // Scanline Overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),

          // Main Content Layout
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Builder(
                      builder: (context) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Minimalist Header
                            _buildMinimalHeader(isLandscape),
                            SizedBox(height: isLandscape ? 12 : 20),

                            if (_waterfallFocusMode) const Spacer(),

                            // Visualizations
                            if (!_waterfallFocusMode)
                              Expanded(
                                flex: 5,
                                child: isLandscape
                                    ? Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _buildGlassCard(
                                              child: SizedBox.expand(
                                                child: CustomPaint(
                                                  size: Size.infinite,
                                                  painter: WaveformPainter(
                                                    audioData: _currentAudioData,
                                                    history: _audioHistory,
                                                    color: Colors.white.withOpacity(0.8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _buildFftCard(accentColor),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: _buildGlassCard(
                                              child: SizedBox.expand(
                                                child: CustomPaint(
                                                  size: Size.infinite,
                                                  painter: WaveformPainter(
                                                    audioData: _currentAudioData,
                                                    history: _audioHistory,
                                                    color: Colors.white.withOpacity(0.8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Expanded(
                                            flex: 3,
                                            child: _buildFftCard(accentColor),
                                          ),
                                        ],
                                      ),
                              ),
                            if (!_waterfallFocusMode) SizedBox(height: isLandscape ? 12 : 16),

                            // Frequency Focus Card & Interaction Bar
                            if (isLandscape && !_waterfallFocusMode)
                              Row(
                                children: [
                                  _buildGainTrigger(),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildGlassCard(child: _buildFrequencyFocusSlider())),
                                  const SizedBox(width: 16),
                                  _buildSensTrigger(),
                                ],
                              )
                            else ...[
                              _buildGlassCard(child: _buildFrequencyFocusSlider()),
                              if (!_waterfallFocusMode) ...[
                                const SizedBox(height: 16),
                                _buildInteractionBar(),
                              ],
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (useTabletLayout)
                  Container(
                    width: 350,
                    margin: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
                    child: _buildGlassCard(
                      child: SettingsContent(
                        settings: widget.settings,
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Large Edge Dials
          if (_gainPersistent || _isDraggingGain) _buildLargeEdgeDial(isLeft: true, value: _gain, label: "GAIN", color: accentColor),
          if (_sensPersistent || _isDraggingSens) _buildLargeEdgeDial(isLeft: false, value: _sensitivity, label: "SENSITIVITY", color: accentColor),
        ],
      ),
    );
  }

  Widget _buildFftCard(Color accentColor) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onTapDown: (details) => _handleFftTap(details.localPosition, constraints.biggest),
        child: _buildGlassCard(
          child: SizedBox.expand(
            child: CustomPaint(
              size: Size.infinite,
              painter: FftBarChartPainter(
                fftData: _currentFftData,
                peakHoldData: widget.settings.peakHoldEnabled ? _fftService.peakHoldBuffer : null,
                markers: _markers,
                showHarmonics: widget.settings.showHarmonics,
                fundamentalFreq: _detectedTone?.frequency,
                snrValue: widget.settings.showSnr ? _snr : null,
                color: accentColor,
                minFreq: _freqRange.start,
                maxFreq: _freqRange.end,
                sampleRate: _signalSource.sampleRate,
                frequencySkew: widget.settings.frequencySkew,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLargeEdgeDial(
      {required bool isLeft, required double value, required String label, required Color color}) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final dialSize = size.height * _kLargeDialSizeScale;

    final availableHeight = size.height - padding.top - padding.bottom;
    return Positioned(
      top: padding.top + (availableHeight - dialSize) / 2,
      left: isLeft ? -dialSize * _kLargeDialOffsetScale + padding.left : null,
      right: isLeft ? null : -dialSize * _kLargeDialOffsetScale + padding.right,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          double delta = -details.delta.dy * 0.01;
          double newValue = (value + delta).clamp(0.1, 5.0);
          if ((value * 10).floor() != (newValue * 10).floor()) {
            HapticFeedback.selectionClick();
          }
          if (isLeft) {
            setState(() => _gain = newValue);
          } else {
            setState(() => _sensitivity = newValue);
          }
        },
        child: Container(
          key: Key('large_dial_${isLeft ? "left" : "right"}'),
          width: dialSize,
          height: dialSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.8),
            border: Border.all(color: color.withOpacity(0.3), width: 4),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 10,
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: isLeft
                    ? const Alignment(0.85, 0.0)
                    : const Alignment(-0.88, 0.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value.toStringAsFixed(2),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w100,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Colors.white24,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: Size(dialSize, dialSize),
                painter: DialArcPainter(value: value, isLeft: isLeft, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader(bool isLandscape) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "SPECTRAL ANALYSIS",
              style: TextStyle(fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w900, color: Colors.white24),
            ),
            Text(
              _isCapturing ? "LIVE SIGNAL" : "SIGNAL IDLE",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
        const Spacer(),
        if (isLandscape) ...[
          Semantics(
            label: "Capture Toggle",
            button: true,
            child: _buildHeaderAction(
              icon: _isCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              onPressed: _toggleCapture,
              iconColor: _isCapturing ? Colors.redAccent : Colors.white70,
              iconSize: 24,
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (!isLandscape || MediaQuery.of(context).size.shortestSide < 600)
          Semantics(
            label: "Settings",
            button: true,
            child: _buildHeaderAction(icon: Icons.tune_rounded, onPressed: _showSettings),
          ),
        const SizedBox(width: 12),
        Semantics(
          label: "Toggle Focus",
          button: true,
          child: _buildHeaderAction(
            icon: _waterfallFocusMode ? Icons.layers : Icons.layers_outlined,
            onPressed: () => setState(() => _waterfallFocusMode = !_waterfallFocusMode),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required VoidCallback onPressed,
    Color? iconColor,
    double? iconSize,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, size: iconSize ?? 20, color: iconColor ?? Colors.white70),
            onPressed: () {
              HapticFeedback.lightImpact();
              onPressed();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFrequencyFocusSlider() {
    final accentColor = Theme.of(context).colorScheme.secondary;
    final List<Widget> labelWidgets = [];
    if (_detectedTone == null) {
      labelWidgets.add(const Text(
        "FOCUS",
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Colors.white24,
            fontWeight: FontWeight.bold),
      ));
    } else {
      final t = _detectedTone!;
      final freqStr = FrequencyFormatter.format(t.frequency, shortUnit: true);
      labelWidgets.add(SizedBox(
        width: 52,
        child: Text(
          freqStr,
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: Colors.white24,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ));
      labelWidgets.add(const Text(" • ",
          style: TextStyle(fontSize: 10, color: Colors.white10)));
      labelWidgets.add(SizedBox(
        width: 28,
        child: Text(
          t.note,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: Colors.white24,
              fontWeight: FontWeight.bold),
        ),
      ));
      if (t.harmonics.isNotEmpty) {
        labelWidgets.add(const Text(" • ",
            style: TextStyle(fontSize: 10, color: Colors.white10)));
        labelWidgets.add(Text(
          "H: ${t.harmonics.join(', ')}",
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: Colors.white24,
              fontWeight: FontWeight.bold),
        ));
      }
    }

    String rangeText;
    if (widget.settings.signalSource == SignalSourceType.rf) {
      final start = (widget.settings.centerFrequency - widget.settings.rfBandwidth / 2) * 1e6;
      final end = (widget.settings.centerFrequency + widget.settings.rfBandwidth / 2) * 1e6;
      rangeText = "${FrequencyFormatter.format(start, precision: 3)} - ${FrequencyFormatter.format(end, precision: 3)}";
    } else {
      rangeText = "${FrequencyFormatter.format(_freqRange.start)} - ${FrequencyFormatter.format(_freqRange.end)}";
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: labelWidgets,
                ),
              ),
            ),
            Text(
                rangeText,
                style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
        const SizedBox(height: 8),
        RadioDialFocusSlider(
          values: _freqRange,
          min: widget.settings.signalSource == SignalSourceType.rf
              ? (widget.settings.centerFrequency - widget.settings.rfBandwidth / 2) * 1e6
              : 0,
          max: widget.settings.signalSource == SignalSourceType.rf
              ? (widget.settings.centerFrequency + widget.settings.rfBandwidth / 2) * 1e6
              : 22050,
          onChanged: (values) {
            setState(() => _freqRange = values);
          },
          accentColor: accentColor,
        ),
      ],
    );
  }

  Widget _buildInteractionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildGainTrigger(),
        _buildCaptureButton(),
        _buildSensTrigger(),
      ],
    );
  }

  Widget _buildGainTrigger() {
    return Semantics(
      label: "GAIN",
      button: true,
      child: _buildDialTrigger(
        "GAIN",
        _gain,
        (v) => setState(() => _gain = v),
        (active) => setState(() {
          _isDraggingGain = active;
          if (active) _sensPersistent = false;
        }),
        () => setState(() {
          _gainPersistent = !_gainPersistent;
          if (_gainPersistent) _sensPersistent = false;
        }),
      ),
    );
  }

  Widget _buildSensTrigger() {
    return Semantics(
      label: "SENS",
      button: true,
      child: _buildDialTrigger(
        "SENS",
        _sensitivity,
        (v) => setState(() => _sensitivity = v),
        (active) => setState(() {
          _isDraggingSens = active;
          if (active) _gainPersistent = false;
        }),
        () => setState(() {
          _sensPersistent = !_sensPersistent;
          if (_sensPersistent) _gainPersistent = false;
        }),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _toggleCapture,
      child: Semantics(
        label: "Capture Toggle",
        button: true,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                border: Border.all(color: _isCapturing ? Colors.red.withOpacity(0.5) : Colors.white24, width: 2),
                boxShadow: [
                  if (_isCapturing)
                    BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 10 + 10 * _pulseController.value)
                ],
              ),
              child: Icon(
                _isCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: _isCapturing ? Colors.redAccent : Colors.white,
                size: 32,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDialTrigger(
    String label,
    double value,
    ValueChanged<double> onChanged,
    ValueChanged<bool> onActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      key: Key('trigger_$label'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onVerticalDragStart: (_) => onActive(true),
      onVerticalDragEnd: (_) => onActive(false),
      onVerticalDragCancel: () => onActive(false),
      onVerticalDragUpdate: (details) {
        // Simple vertical drag for adjustment
        double delta = -details.delta.dy * 0.01;
        double newValue = (value + delta).clamp(0.1, 5.0);
        if ((value * 10).floor() != (newValue * 10).floor()) {
          HapticFeedback.selectionClick();
        }
        onChanged(newValue);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24)),
        ],
      ),
    );
  }
}
