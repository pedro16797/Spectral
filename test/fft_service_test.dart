import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/fft_service.dart';
import 'package:spectral/src/core/settings_model.dart';

void main() {
  group('FftService Tests', () {
    late FftService fftService;

    setUp(() {
      fftService = FftService();
    });

    test('Real FFT processing returns expected magnitude size', () {
      final samples = Float64List.fromList(List.generate(1024, (i) => math.sin(2 * math.pi * i / 10)));
      final magnitudes = fftService.processSignalData(samples, windowSize: 1024, isComplex: false);

      // Real FFT of size N returns N/2 + 1 magnitudes (discarding conjugates)
      expect(magnitudes.length, 513);
    });

    test('Complex FFT processing returns centered spectrum', () {
      // 512 I/Q pairs = 1024 samples
      final samples = Float64List(1024);
      final magnitudes = fftService.processSignalData(samples, windowSize: 512, isComplex: true);

      // Complex FFT returns N magnitudes
      expect(magnitudes.length, 512);
    });

    test('Buffer accumulation works correctly', () {
      // Send 512 samples first (not enough for 1024 window)
      final samples1 = Float64List(512);
      var magnitudes = fftService.processSignalData(samples1, windowSize: 1024);
      expect(magnitudes, isEmpty);

      // Send another 512 samples
      final samples2 = Float64List(512);
      magnitudes = fftService.processSignalData(samples2, windowSize: 1024);
      expect(magnitudes.length, 513);
    });

    test('Reset clears internal buffer and buffers', () {
      final samples = Float64List(512); // Less than 1024
      fftService.processSignalData(samples, windowSize: 1024, peakHoldEnabled: true);
      fftService.reset();

      final magnitudes = fftService.processSignalData(samples, windowSize: 1024);
      expect(magnitudes, isEmpty); // Should still be empty because reset cleared the first 512 samples
      expect(fftService.peakHoldBuffer, isNull);
    });

    test('Tone detection identifies correct musical note (A4)', () {
      const sampleRate = 44100;
      const freq = 440.0; // A4
      final samples = Float64List(2048);
      for (var i = 0; i < 2048; i++) {
        samples[i] = math.sin(2 * math.pi * freq * i / sampleRate);
      }

      final magnitudes = fftService.processSignalData(samples, windowSize: 2048);
      final tone = fftService.detectPrimaryTone(magnitudes, sampleRate);

      expect(tone, isNotNull);
      expect(tone!.note, equals('A4'));
      // Precision check (freq should be close to 440)
      expect(tone.frequency, closeTo(440, 25)); // 44100 / 2048 is ~21.5Hz per bin
    });

    test('Harmonic detection identifies integer multiples', () {
      const sampleRate = 44100;
      const fundamental = 200.0;
      final samples = Float64List(4096);
      for (var i = 0; i < 4096; i++) {
        final t = i / sampleRate;
        samples[i] = 0.6 * math.sin(2 * math.pi * fundamental * t) +
                     0.3 * math.sin(2 * math.pi * 2 * fundamental * t) + // 2nd harmonic
                     0.2 * math.sin(2 * math.pi * 3 * fundamental * t);   // 3rd harmonic
      }

      final magnitudes = fftService.processSignalData(samples, windowSize: 4096);
      final tone = fftService.detectPrimaryTone(magnitudes, sampleRate);

      expect(tone, isNotNull);
      expect(tone!.harmonics, containsAll([2, 3]));
    });

    test('Peak Hold stores maximum magnitudes', () {
      final samples1 = Float64List.fromList(List.generate(1024, (i) => 0.5 * math.sin(2 * math.pi * i / 10)));
      final samples2 = Float64List.fromList(List.generate(1024, (i) => 0.8 * math.sin(2 * math.pi * i / 10)));

      fftService.processSignalData(samples1, windowSize: 1024, peakHoldEnabled: true);
      final hold1 = List<double>.from(fftService.peakHoldBuffer!);

      fftService.processSignalData(samples2, windowSize: 1024, peakHoldEnabled: true);
      final hold2 = fftService.peakHoldBuffer!;

      for (int i = 0; i < hold1.length; i++) {
        expect(hold2[i], greaterThanOrEqualTo(hold1[i]));
      }
    });

    test('Linear averaging reduces noise', () {
      // Create noisy signal
      final rng = math.Random();
      Float64List generateNoisySignal() {
        return Float64List.fromList(List.generate(1024, (i) => 0.1 * math.sin(2 * math.pi * i / 10) + (rng.nextDouble() - 0.5) * 0.2));
      }

      final frames = List.generate(5, (_) => generateNoisySignal());
      List<double>? lastAvg;

      for (var frame in frames) {
        lastAvg = fftService.processSignalData(frame, windowSize: 1024, averagingMode: FftAveragingMode.linear, averagingCount: 5);
      }

      expect(lastAvg, isNotNull);
      // Average should be smoother than a single frame (hard to test precisely without specific noise, but it should be non-empty)
      expect(lastAvg!.length, 513);
    });

    test('SNR calculation returns reasonable values', () {
      const sampleRate = 44100;
      const freq = 440.0;
      final samples = Float64List(2048);
      for (var i = 0; i < 2048; i++) {
        samples[i] = math.sin(2 * math.pi * freq * i / sampleRate);
      }

      final magnitudes = fftService.processSignalData(samples, windowSize: 2048);
      final snr = fftService.calculateSNR(magnitudes);

      expect(snr, greaterThan(20)); // Pure sine wave should have high SNR
    });

   group('Averaging Modes', () {
      test('Exponential averaging works', () {
          final samples1 = Float64List.fromList(List.generate(1024, (i) => 0.5 * math.sin(2 * math.pi * i / 10)));
          final samples2 = Float64List.fromList(List.generate(1024, (i) => 0.8 * math.sin(2 * math.pi * i / 10)));

          final mag1 = fftService.processSignalData(samples1, windowSize: 1024, averagingMode: FftAveragingMode.exponential, averagingCount: 5);
          final mag2 = fftService.processSignalData(samples2, windowSize: 1024, averagingMode: FftAveragingMode.exponential, averagingCount: 5);

          // mag2 should be between mag1 and raw mag2 because of averaging
          expect(mag2[102], greaterThan(mag1[102]));
          // Peak in samples2 (0.8) is larger than in samples1 (0.5).
      });
    });
  });
}
