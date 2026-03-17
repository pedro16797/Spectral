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

class SpectralApp extends StatelessWidget {
  const SpectralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: LocalizationHelper.get('app.name'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SpectralHomePage(),
    );
  }
}

class SpectralHomePage extends StatefulWidget {
  const SpectralHomePage({super.key});

  @override
  State<SpectralHomePage> createState() => _SpectralHomePageState();
}

class _SpectralHomePageState extends State<SpectralHomePage> {
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

  @override
  void initState() {
    super.initState();
    _isDemoMode = Uri.base.queryParameters['demo'] == 'true';
    _setupAudio();
  }

  void _setupAudio() {
    _audioSubscription = _audioService.audioDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentAudioData = data;
          final fft = _fftService.processAudioData(data);
          _currentFftData = fft;
          if (fft.isNotEmpty) {
            _fftHistory.insert(0, fft);
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
        samples[i] = 0.5 * math.sin(phase + (i / 512.0) * 10 * math.pi) +
                     0.3 * math.sin(phase * 2 + (i / 512.0) * 40 * math.pi);
      }
      if (mounted) {
        setState(() {
          _currentAudioData = samples;
          final fft = _fftService.processAudioData(samples);
          _currentFftData = fft;
          if (fft.isNotEmpty) {
            _fftHistory.insert(0, fft);
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
          setState(() {
            _isCapturing = true;
          });
        } else {
          final hasPermission = await _audioService.checkPermission();
          if (hasPermission) {
            await _audioService.startCapture();
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
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationHelper.get('app.name')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black12,
                ),
                child: ClipRect(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: WaveformPainter(
                        audioData: _currentAudioData,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black12,
                ),
                child: ClipRect(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: WaterfallPainter(
                        fftHistory: List.from(_fftHistory),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black12,
                ),
                child: ClipRect(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: FftBarChartPainter(
                        fftData: _currentFftData,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _toggleCapture,
                child: Text(_isCapturing
                    ? LocalizationHelper.get('common.stop_capture')
                    : LocalizationHelper.get('common.start_capture')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
