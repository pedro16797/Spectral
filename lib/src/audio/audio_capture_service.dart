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
      return await _audioRecorder.hasPermission();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> startCapture() async {
    try {
      if (await _audioRecorder.isRecording()) return;

      if (await _audioRecorder.hasPermission()) {
        final config = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        );

        final stream = await _audioRecorder.startStream(config);

        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = stream.listen((data) {
          if (!_audioDataController.isClosed) {
            final normalizedData = AudioUtils.convertPcmToDouble(data);
            _audioDataController.add(normalizedData);
          }
        }, onError: (error) {
          debugPrint("Audio stream error: $error");
        });
      }
    } catch (e) {
      debugPrint("Audio capture error: $e");
    }
  }

  @override
  Future<void> stopCapture() async {
    try {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (e) {
      debugPrint("Error stopping audio capture: $e");
    }
  }

  @override
  void dispose() {
    _audioDataController.close();
    _audioRecorder.dispose();
  }
}
