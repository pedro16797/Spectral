import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'src/audio/audio_capture_service.dart';
import 'src/core/fft_service.dart';
import 'src/ui/waveform_painter.dart';
import 'src/ui/fft_bar_chart_painter.dart';
import 'src/ui/waterfall_painter.dart';
import 'src/utils/localization_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalizationHelper.load('en');
  runApp(const SpectralApp());
}

class SpectralApp extends StatefulWidget {
  const SpectralApp({super.key});

  @override
  State<SpectralApp> createState() => _SpectralAppState();
}

class _SpectralAppState extends State<SpectralApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: LocalizationHelper.get('app.name'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFF007AFF),
          surface: Color(0xFF1C1C1E),
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: SpectralHomePage(onToggleTheme: _toggleTheme, themeMode: _themeMode),
    );
  }
}

class SpectralHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const SpectralHomePage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<SpectralHomePage> createState() => _SpectralHomePageState();
}

class DialArcPainter extends CustomPainter {
  final double value;
  final bool isLeft;
  DialArcPainter({required this.value, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final sweep = (value / 5.0) * math.pi;
    final startAngle = isLeft ? -math.pi / 2 : math.pi / 2;

    final paint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      isLeft ? sweep : -sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant DialArcPainter oldDelegate) => oldDelegate.value != value;
}

class _SpectralHomePageState extends State<SpectralHomePage> with TickerProviderStateMixin {
  final AudioCaptureService _audioService = AudioCaptureService();
  final FftService _fftService = FftService();
  StreamSubscription<Float64List>? _audioSubscription;
  Float64List _currentAudioData = Float64List(0);
  final List<Float64List> _audioHistory = [];
  List<double> _currentFftData = [];
  final List<List<double>> _fftHistory = [];
  static const int _maxHistory = 40;
  bool _isCapturing = false;
  bool _isDemoMode = false;
  Timer? _demoTimer;

  double _gain = 1.0;
  double _sensitivity = 1.0;
  RangeValues _freqRange = const RangeValues(0, 22050);

  bool _isAdjustingGain = false;
  bool _isAdjustingSens = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isDemoMode = Uri.base.queryParameters['demo'] == 'true';
    _setupAudio();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  void _setupAudio() {
    _audioSubscription = _audioService.audioDataStream.listen((data) {
      if (mounted) {
        setState(() {
          final processedAudio = Float64List.fromList(data.map((x) => x * _gain).toList());

          if (_currentAudioData.isNotEmpty) {
            _audioHistory.insert(0, _currentAudioData);
            if (_audioHistory.length > 5) _audioHistory.removeLast();
          }
          _currentAudioData = processedAudio;

          final fft = _fftService.processAudioData(data);
          final adjustedFft = fft.map((x) => x * _sensitivity).toList();
          _currentFftData = adjustedFft;
          if (adjustedFft.isNotEmpty) {
            _fftHistory.insert(0, adjustedFft);
            if (_fftHistory.length > _maxHistory) {
              _fftHistory.removeLast();
            }
          }
        });
      }
    });
  }

  void _startDemoData() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final samples = Float64List(512);
      final phase = DateTime.now().millisecondsSinceEpoch / 1000.0 * 2 * math.pi;
      for (var i = 0; i < 512; i++) {
        samples[i] = (0.4 * math.sin(phase + (i / 512.0) * 12 * math.pi) +
                     0.2 * math.sin(phase * 2.5 + (i / 512.0) * 45 * math.pi)) * _gain;
      }
      if (mounted) {
        setState(() {
          if (_currentAudioData.isNotEmpty) {
            _audioHistory.insert(0, _currentAudioData);
            if (_audioHistory.length > 5) _audioHistory.removeLast();
          }
          _currentAudioData = samples;

          final fft = _fftService.processAudioData(samples);
          final adjustedFft = fft.map((x) => x * _sensitivity).toList();
          _currentFftData = adjustedFft;
          if (adjustedFft.isNotEmpty) {
            _fftHistory.insert(0, adjustedFft);
            if (_fftHistory.length > _maxHistory) {
              _fftHistory.removeLast();
            }
          }
        });
      }
    });
  }

  Future<void> _toggleCapture() async {
    try {
      if (_isCapturing) {
        if (_isDemoMode) {
          _demoTimer?.cancel();
          _demoTimer = null;
        } else {
          await _audioService.stopCapture();
        }
        _pulseController.stop();
        setState(() {
          _isCapturing = false;
          _currentAudioData = Float64List(0);
          _audioHistory.clear();
          _currentFftData = [];
          _fftHistory.clear();
        });
      } else {
        if (_isDemoMode) {
          _startDemoData();
          _pulseController.repeat(reverse: true);
          setState(() => _isCapturing = true);
        } else {
          final hasPermission = await _audioService.checkPermission();
          if (hasPermission) {
            await _audioService.startCapture();
            _pulseController.repeat(reverse: true);
            setState(() => _isCapturing = true);
          }
        }
      }
    } catch (e) {
      debugPrint("Capture error: $e");
    }
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _demoTimer?.cancel();
    _pulseController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Liquid Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.6),
                  radius: 1.5,
                  colors: [Color(0xFF001A33), Colors.black],
                ),
              ),
            ),
          ),

          // Waterfall Background
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: CustomPaint(
                painter: WaterfallPainter(
                  fftHistory: List.from(_fftHistory),
                  minFreq: _freqRange.start,
                  maxFreq: _freqRange.end,
                  sampleRate: 44100,
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Minimalist Header
                  _buildMinimalHeader(),
                  const SizedBox(height: 20),

                  // Waveform Glass Card
                  Expanded(
                    flex: 2,
                    child: _buildGlassCard(
                      child: CustomPaint(
                        painter: WaveformPainter(
                          audioData: _currentAudioData,
                          history: List.from(_audioHistory),
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // FFT Focus Card
                  Expanded(
                    flex: 3,
                    child: _buildGlassCard(
                      child: Column(
                        children: [
                          Expanded(
                            child: CustomPaint(
                              painter: FftBarChartPainter(
                                fftData: _currentFftData,
                                color: const Color(0xFF007AFF),
                                minFreq: _freqRange.start,
                                maxFreq: _freqRange.end,
                                sampleRate: 44100,
                              ),
                            ),
                          ),
                          _buildFrequencyFocusSlider(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),


                  // Interaction Bar
                  const SizedBox(height: 24),
                  _buildInteractionBar(),
                ],
              ),
            ),
          ),

          // Large Edge Dials
          if (_isAdjustingGain) _buildLargeEdgeDial(isLeft: true, value: _gain, label: "GAIN"),
          if (_isAdjustingSens) _buildLargeEdgeDial(isLeft: false, value: _sensitivity, label: "SENSITIVITY"),
        ],
      ),
    );
  }

  Widget _buildLargeEdgeDial({required bool isLeft, required double value, required String label}) {
    final size = MediaQuery.of(context).size;
    final dialSize = size.height * 0.4;

    return Positioned(
      top: (size.height - dialSize) / 2,
      left: isLeft ? -dialSize / 2 : null,
      right: isLeft ? null : -dialSize / 2,
      child: IgnorePointer(
        child: Container(
          width: dialSize,
          height: dialSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.8),
            border: Border.all(color: const Color(0xFF007AFF).withOpacity(0.3), width: 4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007AFF).withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 10,
              )
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radial scale markers could go here
              Positioned(
                left: isLeft ? dialSize * 0.6 : null,
                right: isLeft ? null : dialSize * 0.6,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w100, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Spinning arc to show value
              CustomPaint(
                size: Size(dialSize, dialSize),
                painter: DialArcPainter(value: value, isLeft: isLeft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader() {
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
        _buildHeaderAction(icon: Icons.tune_rounded, onPressed: () {}),
        const SizedBox(width: 12),
        _buildHeaderAction(icon: widget.themeMode == ThemeMode.dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined, onPressed: widget.onToggleTheme),
      ],
    );
  }

  Widget _buildHeaderAction({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Colors.white70),
        onPressed: onPressed,
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
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Text("FOCUS", style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: RangeSlider(
              values: _freqRange,
              min: 0,
              max: 22050,
              activeColor: const Color(0xFF007AFF),
              inactiveColor: Colors.white10,
              onChanged: (values) => setState(() => _freqRange = values),
            ),
          ),
          const SizedBox(width: 12),
          Text("${(_freqRange.end / 1000).toStringAsFixed(1)}kHz", style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildInteractionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildDialTrigger("GAIN", _gain, (v) => setState(() => _gain = v), (active) => setState(() => _isAdjustingGain = active)),
        GestureDetector(
          onTap: _toggleCapture,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isCapturing ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  border: Border.all(color: _isCapturing ? Colors.red.withOpacity(0.5) : Colors.white24, width: 2),
                  boxShadow: [
                    if (_isCapturing) BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 10 + 10 * _pulseController.value)
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
        _buildDialTrigger("SENS", _sensitivity, (v) => setState(() => _sensitivity = v), (active) => setState(() => _isAdjustingSens = active)),
      ],
    );
  }

  Widget _buildDialTrigger(String label, double value, ValueChanged<double> onChanged, ValueChanged<bool> onActive) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onActive(true),
      onVerticalDragEnd: (_) => onActive(false),
      onVerticalDragCancel: () => onActive(false),
      onVerticalDragUpdate: (details) {
        // Simple vertical drag for adjustment
        double delta = -details.delta.dy * 0.01;
        double newValue = (value + delta).clamp(0.1, 5.0);
        onChanged(newValue);
      },
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24)),
          const SizedBox(height: 4),
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
        ],
      ),
    );
  }
}
