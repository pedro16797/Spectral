import 'dart:typed_data';
import 'dart:math' as math;
import 'package:fftea/fftea.dart';

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

  /// Processes normalized audio samples and returns the FFT magnitudes.
  List<double> processAudioData(Float64List samples) {
    if (samples.isEmpty) return [];

    final sampleCount = samples.length;
    if (sampleCount < 2) return [];

    // Cache FFT instance if the size hasn't changed.
    if (_cachedFft == null || _cachedSize != sampleCount) {
      _cachedFft = FFT(sampleCount);
      _cachedSize = sampleCount;
    }

    try {
      // Apply Hanning window to reduce spectral leakage
      final window = Window.hanning(sampleCount);
      final windowedSamples = Float64List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        windowedSamples[i] = samples[i] * window[i];
      }

      final freq = _cachedFft!.realFft(windowedSamples);
      // discardConjugates() fixes the mirroring issue by keeping 0 to Nyquist
      return freq.discardConjugates().magnitudes();
    } catch (e) {
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
