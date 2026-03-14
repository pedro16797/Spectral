import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioCaptureService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final _audioDataController = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get audioDataStream => _audioDataController.stream;

  Future<bool> checkPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startCapture() async {
    if (await _audioRecorder.hasPermission()) {
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);

      _audioStreamSubscription = stream.listen((data) {
        _audioDataController.add(data);
      });
    }
  }

  Future<void> stopCapture() async {
    await _audioStreamSubscription?.cancel();
    await _audioRecorder.stop();
  }

  void dispose() {
    _audioDataController.close();
    _audioRecorder.dispose();
  }
}
