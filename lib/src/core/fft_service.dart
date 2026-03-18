import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:fftea/fftea.dart';
import 'settings_model.dart';

class ToneInfo {
  final double frequency;
  final String note;
  final List<int> harmonics;

  ToneInfo({
    required this.frequency,
    required this.note,
    required this.harmonics,
  });
}

class FftService {
  FFT? _cachedFft;
  int? _cachedSize;
  Float64List? _cachedWindow;
  FftWindowType? _cachedWindowType;

  // Internal buffer for accumulating samples to match window size
  final List<double> _buffer = [];

  /// Processes normalized audio samples and returns the FFT magnitudes.
  /// It maintains an internal buffer to ensure it processes chunks of [windowSize].
  List<double> processAudioData(Float64List samples, {int windowSize = 1024, FftWindowType windowType = FftWindowType.hanning}) {
    if (samples.isEmpty) return [];

    // Add new samples to buffer
    _buffer.addAll(samples);

    // If we have more than windowSize, we keep only the latest windowSize samples
    // for a simple real-time display. For a true STFT we might want overlap,
    // but here we'll just take the most recent chunk if it's large enough.
    if (_buffer.length < windowSize) {
      return [];
    }

    // Extract the latest windowSize samples
    final processingSamples = Float64List.fromList(
      _buffer.sublist(_buffer.length - windowSize)
    );

    // Clear buffer to avoid indefinite growth, keeping some for overlap if needed in future
    // For now, let's just keep the last windowSize to allow smooth transitions if windowSize changes
    if (_buffer.length > windowSize * 2) {
      _buffer.removeRange(0, _buffer.length - windowSize);
    }

    // Cache FFT instance if the size hasn't changed.
    if (_cachedFft == null || _cachedSize != windowSize) {
      _cachedFft = FFT(windowSize);
      _cachedSize = windowSize;
      _cachedWindow = null; // Reset window if size changed
    }

    // Cache window if type or size changed
    if (_cachedWindow == null || _cachedWindowType != windowType) {
      _cachedWindowType = windowType;
      switch (windowType) {
        case FftWindowType.hanning:
          _cachedWindow = Window.hanning(windowSize);
          break;
        case FftWindowType.hamming:
          _cachedWindow = Window.hamming(windowSize);
          break;
        case FftWindowType.blackman:
          _cachedWindow = Window.blackman(windowSize);
          break;
      }
    }

    try {
      final windowedSamples = Float64List(windowSize);
      for (int i = 0; i < windowSize; i++) {
        windowedSamples[i] = processingSamples[i] * _cachedWindow![i];
      }

      final freq = _cachedFft!.realFft(windowedSamples);
      return freq.discardConjugates().magnitudes();
    } catch (e) {
      debugPrint("FFT processing error: $e");
      return [];
    }
  }

  /// Detects the primary tone and its harmonics.
  ToneInfo? detectPrimaryTone(List<double> magnitudes, int sampleRate) {
    if (magnitudes.isEmpty) return null;

    // Find the peak, skipping DC (index 0)
    double maxMag = 0;
    int peakIndex = -1;
    for (int i = 1; i < magnitudes.length; i++) {
      if (magnitudes[i] > maxMag) {
        maxMag = magnitudes[i];
        peakIndex = i;
      }
    }

    // Threshold to avoid detecting noise as a tone
    if (peakIndex == -1 || maxMag < 0.5) return null;

    // Calculate fundamental frequency
    // N is (magnitudes.length - 1) * 2
    final n = (magnitudes.length - 1) * 2;
    final fundamentalFreq = peakIndex * sampleRate / n;

    // Detect harmonics (check if there are peaks at multiples of peakIndex)
    final harmonics = <int>[];
    for (int h = 2; h <= 5; h++) {
      int hIndex = peakIndex * h;
      if (hIndex < magnitudes.length) {
        // Check if there's a local peak around hIndex
        int actualHIndex = hIndex;
        double localMax = magnitudes[hIndex];
        for (int neighbor = -2; neighbor <= 2; neighbor++) {
          int idx = hIndex + neighbor;
          if (idx >= 0 && idx < magnitudes.length) {
            if (magnitudes[idx] > localMax) {
               localMax = magnitudes[idx];
               actualHIndex = idx;
            }
          }
        }

        // If the peak at actualHIndex is significant relative to the fundamental
        if (magnitudes[actualHIndex] > maxMag * 0.1) {
          harmonics.add(h);
        }
      }
    }

    return ToneInfo(
      frequency: fundamentalFreq,
      note: _frequencyToNote(fundamentalFreq),
      harmonics: harmonics,
    );
  }

  String _frequencyToNote(double freq) {
    if (freq <= 0) return "";

    final notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    // A4 = 440Hz is MIDI note 69
    double midi = 12 * (math.log(freq / 440.0) / math.log(2)) + 69;
    int midiRounded = midi.round();

    if (midiRounded < 0) return "";

    int octave = (midiRounded / 12).floor() - 1;
    String noteName = notes[midiRounded % 12];

    return "$noteName$octave";
  }
}
