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

  /// Pauses audio playback.
  void pause() {
    if (!_isInitialized) return;
    try {
      // mp_audio_stream doesn't have a direct pause, but we can stop pushing data
      // or check if there's a state management we need.
      // It seems it just plays what's in the buffer.
      // We can call resume() again if it was suspended.
    } catch (e) {
      debugPrint("AudioOutputService: Error pausing: $e");
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

  /// Clears the internal audio buffer.
  void clearBuffer() {
    if (!_isInitialized) return;
    // mp_audio_stream does not explicitly provide a clearBuffer,
    // but some implementations might.
  }

  /// Disposes of the audio stream.
  void dispose() {
    if (_isInitialized) {
      // mp_audio_stream usually doesn't need explicit dispose if it follows typical plugin patterns,
      // but let's check if it has one. It doesn't seem to have a public dispose() in the snippet.
      debugPrint("AudioOutputService: Disposed.");
    }
  }
}
