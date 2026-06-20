import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mp_audio_stream/mp_audio_stream.dart';

/// Service to handle real-time PCM audio playback using `mp_audio_stream`.
class AudioOutputService {
  late final AudioStream _audioStream;
  bool _isInitialized = false;
  bool _isResumed = false;

  AudioOutputService() {
    _audioStream = getAudioStream();
  }

  /// Initializes the audio stream with the given configuration.
  void init({int sampleRate = 44100, int channels = 1}) {
    if (_isInitialized) return;
    try {
      _audioStream.init(sampleRate: sampleRate, channels: channels);
      _isInitialized = true;
      debugPrint("AudioOutputService: Initialized with $sampleRate Hz, $channels channels.");
    } catch (e) {
      debugPrint("AudioOutputService: Error initializing: $e");
    }
  }

  /// Resumes audio playback. This MUST be called after user interaction on Web.
  void resume() {
    if (!_isInitialized) return;
    try {
      _audioStream.resume();
      _isResumed = true;
      debugPrint("AudioOutputService: Resumed.");
    } catch (e) {
      debugPrint("AudioOutputService: Error resuming: $e");
    }
  }

  /// Pushes double precision samples to the audio stream.
  /// Samples are expected to be in the range [-1.0, 1.0].
  void push(Float64List samples) {
    if (!_isInitialized || !_isResumed) return;
    try {
      final float32Samples = Float32List.fromList(samples);
      _audioStream.push(float32Samples);
    } catch (e) {
      debugPrint("AudioOutputService: Error pushing samples: $e");
    }
  }

  /// Disposes of the audio stream.
  ///
  /// `mp_audio_stream` does not expose an explicit native teardown in this
  /// version, so we mark the service uninitialized to ensure any further
  /// [push]/[resume] calls become no-ops (guards against use-after-dispose).
  void dispose() {
    _isInitialized = false;
    _isResumed = false;
    debugPrint("AudioOutputService: Disposed.");
  }
}
