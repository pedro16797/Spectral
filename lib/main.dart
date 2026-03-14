import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'src/services/audio_capture_service.dart';
import 'src/ui/waveform_painter.dart';

void main() {
  runApp(const SpectralApp());
}

class SpectralApp extends StatelessWidget {
  const SpectralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spectral',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        brightness: Brightness.dark,
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
  Uint8List _currentAudioData = Uint8List(0);
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _setupAudio();
  }

  void _setupAudio() {
    _audioService.audioDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentAudioData = data;
        });
      }
    });
  }

  Future<void> _toggleCapture() async {
    if (_isCapturing) {
      await _audioService.stopCapture();
      setState(() {
        _isCapturing = false;
        _currentAudioData = Uint8List(0);
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
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spectral'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRect(
                  child: CustomPaint(
                    painter: WaveformPainter(
                      audioData: _currentAudioData,
                      color: Colors.greenAccent,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _toggleCapture,
                child: Text(_isCapturing ? 'Stop Capture' : 'Start Capture'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
