import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
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
        scaffoldBackgroundColor: const Color(0xFF020204),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7000FF),
          surface: Color(0xFF050508),
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

class _SpectralHomePageState extends State<SpectralHomePage> with TickerProviderStateMixin {
  final AudioCaptureService _audioService = AudioCaptureService();
  final FftService _fftService = FftService();
  StreamSubscription<Float64List>? _audioSubscription;
  Float64List _currentAudioData = Float64List(0);
  List<double> _currentFftData = [];
  final List<List<double>> _fftHistory = [];
  static const int _maxHistory = 40;
  bool _isCapturing = false;
  bool _isDemoMode = false;
  Timer? _demoTimer;

  double _gain = 1.0;
  double _sensitivity = 1.0;

  late AnimationController _coreController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _isDemoMode = Uri.base.queryParameters['demo'] == 'true';
    _setupAudio();

    _coreController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  void _setupAudio() {
    _audioSubscription = _audioService.audioDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentAudioData = Float64List.fromList(data.map((x) => x * _gain).toList());
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
        setState(() {
          _isCapturing = false;
          _currentAudioData = Float64List(0);
          _currentFftData = [];
          _fftHistory.clear();
        });
      } else {
        if (_isDemoMode) {
          _startDemoData();
          setState(() => _isCapturing = true);
        } else {
          final hasPermission = await _audioService.checkPermission();
          if (hasPermission) {
            await _audioService.startCapture();
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
    _coreController.dispose();
    _rotationController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background - Deep Space
          Positioned.fill(
            child: Container(color: const Color(0xFF020204)),
          ),

          // Sector: Waterfall (Background Projection)
          Positioned(
            top: 0, bottom: 0, left: 0, right: 0,
            child: Opacity(
              opacity: 0.15,
              child: Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(-0.5),
                alignment: Alignment.center,
                child: CustomPaint(
                  painter: WaterfallPainter(fftHistory: List.from(_fftHistory)),
                ),
              ),
            ),
          ),

          // Grid Overlay
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(painter: _TacticalGridPainter()),
            ),
          ),

          // Top Info
          Positioned(
            top: 40, left: 24,
            child: _buildHeaderInfo(),
          ),

          // Main Center: SPECTRAL CORE
          Center(
            child: _buildSpectralCore(),
          ),

          // Sector: Waveform (Floating Projection)
          Positioned(
            top: 100, left: 0, right: 0,
            height: 120,
            child: _buildFloatingProjection(
              child: CustomPaint(
                painter: WaveformPainter(
                  audioData: _currentAudioData,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),

          // Sector: FFT (Floating Projection Bottom)
          Positioned(
            bottom: 120, left: 0, right: 0,
            height: 100,
            child: _buildFloatingProjection(
              child: CustomPaint(
                painter: FftBarChartPainter(
                  fftData: _currentFftData,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ),

          // Integrated Holographic Controls
          _buildHolographicControls(),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocalizationHelper.get('app.name').toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
            shadows: [Shadow(color: Theme.of(context).colorScheme.primary, blurRadius: 20)],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Text(
            "COORD_SYS_V4 // ${_isCapturing ? 'STREAMING' : 'IDLE'}",
            style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildSpectralCore() {
    return GestureDetector(
      onTap: _toggleCapture,
      child: AnimatedBuilder(
        animation: _coreController,
        builder: (context, child) {
          final pulse = 1.0 + (0.1 * math.sin(_coreController.value * 2 * math.pi));
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer Rotating Ring
              RotationTransition(
                turns: _rotationController,
                child: CustomPaint(
                  size: const Size(260, 260),
                  painter: _CoreRingPainter(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                ),
              ),
              // Inner Pulsing Core
              Container(
                width: 120 * pulse, height: 120 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (_isCapturing ? Colors.redAccent : Theme.of(context).colorScheme.primary).withOpacity(0.4),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                    color: _isCapturing ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isCapturing ? Colors.redAccent : Theme.of(context).colorScheme.primary).withOpacity(0.5),
                      blurRadius: 30,
                    )
                  ],
                ),
                child: Icon(
                  _isCapturing ? Icons.stop_circle_outlined : Icons.radio_button_checked,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFloatingProjection({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: child,
    );
  }

  Widget _buildHolographicControls() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            // Gain Arc (Left Side)
            Positioned(
              left: -80, top: 0, bottom: 0,
              width: 200,
              child: _buildArcControl(
                label: "GAIN",
                value: _gain,
                onChanged: (v) => setState(() => _gain = v),
              ),
            ),
            // Sensitivity Arc (Right Side)
            Positioned(
              right: -80, top: 0, bottom: 0,
              width: 200,
              child: _buildArcControl(
                label: "SENS",
                value: _sensitivity,
                isRight: true,
                onChanged: (v) => setState(() => _sensitivity = v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArcControl({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    bool isRight = false,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RotatedBox(
          quarterTurns: isRight ? 1 : 3,
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.white24)),
              SizedBox(
                width: 300,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    activeTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    inactiveTrackColor: Colors.white10,
                    thumbColor: Theme.of(context).colorScheme.primary,
                    thumbShape: const RectangularSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(value: value, min: 0.1, max: 5.0, onChanged: onChanged),
                ),
              ),
              Text(value.toStringAsFixed(1), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoreRingPainter extends CustomPainter {
  final Color color;
  _CoreRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);

    // Draw tick marks
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final start = Offset(
        size.width / 2 + (size.width / 2 - 10) * math.cos(angle),
        size.height / 2 + (size.width / 2 - 10) * math.sin(angle),
      );
      final end = Offset(
        size.width / 2 + (size.width / 2 + 5) * math.cos(angle),
        size.height / 2 + (size.width / 2 + 5) * math.sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TacticalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.15)
      ..strokeWidth = 0.5;

    for (var i = 0.0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (var i = 0.0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RectangularSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  const RectangularSliderThumbShape({this.enabledThumbRadius = 6.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(enabledThumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromCenter(center: center, width: 4, height: 16),
      paint,
    );

    // Glow
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 8, height: 20),
      Paint()..color = sliderTheme.thumbColor!.withOpacity(0.2)..style = PaintingStyle.fill,
    );
  }
}
