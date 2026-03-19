import 'dart:async';
import 'dart:typed_data';

abstract class SignalSource {
  /// Stream of signal data.
  /// For real signals, each element is a sample.
  /// For complex signals, elements are interleaved [I, Q, I, Q, ...].
  Stream<Float64List> get dataStream;

  /// Checks if necessary permissions (e.g., Microphone, USB) are granted.
  Future<bool> checkPermission();

  /// Starts the signal capture.
  Future<void> startCapture();

  /// Stops the signal capture.
  Future<void> stopCapture();

  /// Disposes of resources.
  void dispose();

  /// Returns the current sample rate of the source.
  int get sampleRate;

  /// Indicates if the signal is complex (I/Q).
  bool get isComplex;
}
