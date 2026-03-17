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
  RangeValues _freqRange = const RangeValues(0, 22050);

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
        _pulseController.stop();
        setState(() {
          _isCapturing = false;
          _currentAudioData = Float64List(0);
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

                  // Waterfall Background-ish Card
                  Expanded(
                    flex: 2,
                    child: _buildGlassCard(
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

                  // Interaction Bar
                  const SizedBox(height: 24),
                  _buildInteractionBar(),
                ],
              ),
            ),
          ),
        ],
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
        _buildSliderControl("GAIN", _gain, (v) => setState(() => _gain = v)),
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
        _buildSliderControl("SENS", _sensitivity, (v) => setState(() => _sensitivity = v)),
      ],
    );
  }

  Widget _buildSliderControl(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white24)),
        SizedBox(
          width: 100,
          child: Slider(
            value: value,
            min: 0.1,
            max: 5.0,
            activeColor: Colors.white70,
            inactiveColor: Colors.white10,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
