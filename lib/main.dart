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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFFBC13FE),
          surface: Color(0xFF0A0A0C),
          onSurface: Color(0xFFE0E0E0),
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
  static const int _maxHistory = 50;
  bool _isCapturing = false;
  bool _isDemoMode = false;
  Timer? _demoTimer;
  bool _showSettings = false;
  late AnimationController _pulseController;

  double _gain = 1.0;
  double _sensitivity = 1.0;

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
          // Apply gain to audio data
          _currentAudioData = Float64List.fromList(data.map((x) => x * _gain).toList());

          final fft = _fftService.processAudioData(data);
          // Apply sensitivity to FFT data
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
        // Use a more complex signal for demo: two sines combined
        samples[i] = (0.5 * math.sin(phase + (i / 512.0) * 10 * math.pi) +
                     0.3 * math.sin(phase * 2 + (i / 512.0) * 40 * math.pi)) * _gain;
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
          setState(() {
            _isCapturing = true;
          });
        } else {
          final hasPermission = await _audioService.checkPermission();
          if (hasPermission) {
            await _audioService.startCapture();
            _pulseController.repeat(reverse: true);
            setState(() {
              _isCapturing = true;
            });
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(LocalizationHelper.get('common.permission_denied'))),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${LocalizationHelper.get('common.error')}: $e')),
        );
      }
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

  Widget _buildTechHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalizationHelper.get('app.name').toUpperCase(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              Text(
                "SYSTEM STATUS: ${_isCapturing ? 'ACTIVE' : 'READY'}",
                style: TextStyle(
                  color: _isCapturing ? Colors.greenAccent : Colors.white24,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildHeaderIcon(
            icon: Icons.tune,
            onPressed: () => setState(() => _showSettings = !_showSettings),
          ),
          const SizedBox(width: 16),
          _buildHeaderIcon(
            icon: widget.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon({required IconData icon, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          ),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildHudModule({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D11).withOpacity(0.8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Scanline effect
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(
                painter: _ScanlinePainter(),
              ),
            ),
          ),
          // Corner Brackets
          Positioned(
            top: 0, left: 0,
            child: _buildCornerBracket(top: true, left: true),
          ),
          Positioned(
            top: 0, right: 0,
            child: _buildCornerBracket(top: true, left: false),
          ),
          Positioned(
            bottom: 0, left: 0,
            child: _buildCornerBracket(top: false, left: true),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: _buildCornerBracket(top: false, left: false),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4, height: 4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBracket({required bool top, required bool left}) {
    final color = Theme.of(context).colorScheme.primary.withOpacity(0.5);
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: color, width: 2) : BorderSide.none,
          bottom: !top ? BorderSide(color: color, width: 2) : BorderSide.none,
          left: left ? BorderSide(color: color, width: 2) : BorderSide.none,
          right: !left ? BorderSide(color: color, width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;

                final visualizations = [
                  _buildHudModule(
                    title: LocalizationHelper.get('visualizations.waveform'),
                    child: CustomPaint(
                      painter: WaveformPainter(
                        audioData: _currentAudioData,
                        color: const Color(0xFF00FF9F),
                      ),
                    ),
                  ),
                  _buildHudModule(
                    title: LocalizationHelper.get('visualizations.waterfall'),
                    child: CustomPaint(
                      painter: WaterfallPainter(
                        fftHistory: List.from(_fftHistory),
                      ),
                    ),
                  ),
                  _buildHudModule(
                    title: LocalizationHelper.get('visualizations.fft'),
                    child: CustomPaint(
                      painter: FftBarChartPainter(
                        fftData: _currentFftData,
                        color: const Color(0xFF00B2FF),
                      ),
                    ),
                  ),
                ];

                return Column(
                  children: [
                    _buildTechHeader(),
                    Expanded(
                      child: isWide
                          ? GridView.count(
                              crossAxisCount: 2,
                              padding: const EdgeInsets.all(8),
                              children: visualizations,
                            )
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: visualizations.map((v) => Expanded(child: v)).toList(),
                            ),
                    ),
                    const SizedBox(height: 100), // Space for capture hub
                  ],
                );
              },
            ),

            // Settings Overlay
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutQuart,
              top: _showSettings ? 100 : -400,
              left: 24,
              right: 24,
              child: _buildSettingsPanel(),
            ),

            // Capture Control Hub
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: _buildCaptureHub(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureHub() {
    return Center(
      child: GestureDetector(
        onTap: _toggleCapture,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final color = _isCapturing ? Colors.redAccent : Theme.of(context).colorScheme.primary;
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D0D11),
                border: Border.all(
                  color: color,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(_isCapturing ? 0.2 + (0.3 * _pulseController.value) : 0.2),
                    blurRadius: _isCapturing ? 10 + (20 * _pulseController.value) : 10,
                    spreadRadius: _isCapturing ? 2 + (8 * _pulseController.value) : 2,
                  ),
                ],
              ),
              child: Icon(
                _isCapturing ? Icons.stop_rounded : Icons.mic_rounded,
                size: 40,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D11).withOpacity(0.95),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "SYSTEM CALIBRATION",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showSettings = false),
                child: Icon(Icons.close, size: 16, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTechSlider(
            label: LocalizationHelper.get('settings.gain'),
            value: _gain,
            onChanged: (v) => setState(() => _gain = v),
          ),
          const SizedBox(height: 24),
          _buildTechSlider(
            label: LocalizationHelper.get('settings.sensitivity'),
            value: _sensitivity,
            onChanged: (v) => setState(() => _sensitivity = v),
          ),
        ],
      ),
    );
  }

  Widget _buildTechSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5),
            ),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            min: 0.1,
            max: 5.0,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F0FF)
      ..strokeWidth = 1.0;

    for (var i = 0.0; i < size.height; i += 4.0) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
