import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../utils/audio_utils.dart';
import '../core/signal_source.dart';

class AudioCaptureService implements SignalSource {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final _audioDataController = StreamController<Float64List>.broadcast();

  @override
  Stream<Float64List> get dataStream => _audioDataController.stream;

  // Added for backward compatibility (optional, but good practice if other files use it)
  Stream<Float64List> get audioDataStream => dataStream;

  @override
  int get sampleRate => 44100;

  @override
  bool get isComplex => false;

  @override
  Future<bool> checkPermission() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      debugPrint("AudioCaptureService: Permission check result: $hasPermission");
      return hasPermission;
    } catch (e) {
      debugPrint("AudioCaptureService: Error checking permission: $e");
      return false;
    }
  }

  @override
  Future<void> startCapture() async {
    try {
      if (await _audioRecorder.isRecording()) {
        debugPrint("AudioCaptureService: Already recording.");
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        debugPrint("AudioCaptureService: Starting stream with sample rate $sampleRate...");
        final config = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        );

        final stream = await _audioRecorder.startStream(config);

        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = stream.listen((data) {
          if (!_audioDataController.isClosed) {
            try {
              final normalizedData = AudioUtils.convertPcmToDouble(data);
              _audioDataController.add(normalizedData);
            } catch (e) {
              debugPrint("AudioCaptureService: Normalization error: $e, Data length: ${data.length}, Offset: ${data.offsetInBytes}");
            }
          }
        }, onError: (error) {
          debugPrint("AudioCaptureService: Audio stream error: $error");
        }, onDone: () {
          debugPrint("AudioCaptureService: Audio stream closed.");
        });
        debugPrint("AudioCaptureService: Stream started successfully.");
      } else {
        debugPrint("AudioCaptureService: Missing microphone permission.");
      }
    } catch (e) {
      debugPrint("AudioCaptureService: Capture error: $e");
    }
  }

  @override
  Future<void> stopCapture() async {
    try {
      debugPrint("AudioCaptureService: Stopping capture...");
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
      debugPrint("AudioCaptureService: Capture stopped.");
    } catch (e) {
      debugPrint("AudioCaptureService: Error stopping audio capture: $e");
    }
  }

  @override
  void dispose() {
    debugPrint("AudioCaptureService: Disposing...");
    _audioDataController.close();
    _audioRecorder.dispose();
  }
}
