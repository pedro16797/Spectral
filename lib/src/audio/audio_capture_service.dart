import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import '../utils/audio_utils.dart';

class AudioCaptureService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final _audioDataController = StreamController<Float64List>.broadcast();

  Stream<Float64List> get audioDataStream => _audioDataController.stream;

  Future<bool> checkPermission() async {
    try {
      return await _audioRecorder.hasPermission();
    } catch (e) {
      return false;
    }
  }

  Future<void> startCapture() async {
    try {
      if (await _audioRecorder.isRecording()) return;

      if (await _audioRecorder.hasPermission()) {
        const config = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
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
          // Handle stream errors
        });
      }
    } catch (e) {
      // Handle potential hardware access errors
    }
  }

  Future<void> stopCapture() async {
    try {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (e) {
      // Handle errors during stop
    }
  }

  void dispose() {
    _audioDataController.close();
    _audioRecorder.dispose();
  }
}
