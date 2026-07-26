import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/channel_extractor.dart';

/// Builds [pairs] interleaved I/Q samples of a complex tone at [toneHz].
Float64List complexTone(double toneHz, double sampleRate, int pairs,
    {double amplitude = 1.0, double startPhase = 0.0}) {
  final out = Float64List(pairs * 2);
  for (int n = 0; n < pairs; n++) {
    final phase = startPhase + 2 * math.pi * toneHz * n / sampleRate;
    out[n * 2] = amplitude * math.cos(phase);
    out[n * 2 + 1] = amplitude * math.sin(phase);
  }
  return out;
}

/// Mean magnitude of an interleaved I/Q buffer.
double meanMagnitude(Float64List iq) {
  if (iq.isEmpty) return 0;
  double sum = 0;
  final pairs = iq.length ~/ 2;
  for (int n = 0; n < pairs; n++) {
    sum += math.sqrt(iq[n * 2] * iq[n * 2] + iq[n * 2 + 1] * iq[n * 2 + 1]);
  }
  return sum / pairs;
}

/// Average frequency of a complex tone, from the mean phase advance per sample.
double estimateToneHz(Float64List iq, double sampleRate) {
  final pairs = iq.length ~/ 2;
  if (pairs < 2) return 0;
  double sumPhase = 0;
  for (int n = 1; n < pairs; n++) {
    final i0 = iq[(n - 1) * 2], q0 = iq[(n - 1) * 2 + 1];
    final i1 = iq[n * 2], q1 = iq[n * 2 + 1];
    // Phase of sample[n] * conj(sample[n-1]).
    sumPhase += math.atan2(q1 * i0 - i1 * q0, i1 * i0 + q1 * q0);
  }
  return (sumPhase / (pairs - 1)) * sampleRate / (2 * math.pi);
}

void main() {
  group('planChannel', () {
    const capture = 2400000.0;
    const center = 100000000.0;

    test('centres the offset on the selection', () {
      final plan = planChannel(
        startHz: 100.4e6,
        endHz: 100.6e6,
        centerHz: center,
        captureRateHz: capture,
      );
      expect(plan.offsetHz, closeTo(500000, 1));
    });

    test('decimates to at least the requested width', () {
      final plan = planChannel(
        startHz: 99.9e6,
        endHz: 100.1e6, // 200 kHz
        centerHz: center,
        captureRateHz: capture,
      );
      final channelRate = capture / plan.decimation;
      expect(channelRate, greaterThanOrEqualTo(200000));
      // ...without wasting bandwidth: one step further would be too narrow.
      expect(capture / (plan.decimation + 1), lessThan(200000));
    });

    test('never produces a channel too narrow to carry audio', () {
      final plan = planChannel(
        startHz: 100.0e6,
        endHz: 100.001e6, // 1 kHz — far too narrow
        centerHz: center,
        captureRateHz: capture,
      );
      expect(capture / plan.decimation,
          greaterThanOrEqualTo(kMinChannelBandwidthHz));
    });

    test('keeps the channel inside the captured band', () {
      // Selection well beyond the capture edge; the offset must be pulled back
      // so the channel still lands on real signal.
      final plan = planChannel(
        startHz: 105.0e6,
        endHz: 105.2e6,
        centerHz: center,
        captureRateHz: capture,
      );
      final channelRate = capture / plan.decimation;
      expect(plan.offsetHz.abs() + channelRate / 2,
          lessThanOrEqualTo(capture / 2 + 1));
    });

    test('a full-band selection is a passthrough', () {
      final plan = planChannel(
        startHz: center - capture / 2,
        endHz: center + capture / 2,
        centerHz: center,
        captureRateHz: capture,
      );
      expect(plan.decimation, 1);
      expect(plan.offsetHz, closeTo(0, 1));
    });

    test('degenerate capture rate is handled', () {
      final plan = planChannel(
        startHz: 1,
        endHz: 2,
        centerHz: 0,
        captureRateHz: 0,
      );
      expect(plan.decimation, 1);
    });
  });

  group('ChannelExtractor', () {
    const sampleRate = 1200000.0;

    test('shifts the selected tone down to DC', () {
      final extractor = ChannelExtractor();
      // A tone 300 kHz above centre, mixed down by 300 kHz, should land at 0.
      final input = complexTone(300000, sampleRate, 4096);
      final out = extractor.process(
        input,
        offsetHz: 300000,
        sampleRate: sampleRate,
        decimation: 4,
      );
      expect(estimateToneHz(out, sampleRate / 4), closeTo(0, 50));
    });

    test('a tone already at the centre is left at DC', () {
      final extractor = ChannelExtractor();
      final input = complexTone(0, sampleRate, 2048);
      final out = extractor.process(
        input,
        offsetHz: 0,
        sampleRate: sampleRate,
        decimation: 4,
      );
      expect(estimateToneHz(out, sampleRate / 4), closeTo(0, 10));
      // A DC tone survives averaging with its amplitude intact.
      expect(meanMagnitude(out), closeTo(1.0, 0.01));
    });

    test('an off-channel tone is attenuated by the decimating average', () {
      final wanted = ChannelExtractor().process(
        complexTone(200000, sampleRate, 4096),
        offsetHz: 200000,
        sampleRate: sampleRate,
        decimation: 8,
      );
      // Same decimation, but the tone sits far outside the channel.
      final unwanted = ChannelExtractor().process(
        complexTone(500000, sampleRate, 4096),
        offsetHz: 200000,
        sampleRate: sampleRate,
        decimation: 8,
      );
      expect(meanMagnitude(unwanted), lessThan(meanMagnitude(wanted) * 0.3));
    });

    test('output rate matches the decimation factor', () {
      final extractor = ChannelExtractor();
      final out = extractor.process(
        complexTone(0, sampleRate, 1000),
        offsetHz: 0,
        sampleRate: sampleRate,
        decimation: 10,
      );
      expect(out.length ~/ 2, 100);
    });

    test('carries partial groups across frames without losing samples', () {
      final extractor = ChannelExtractor();
      int total = 0;
      // 30 samples per frame with decimation 4 leaves a remainder each time,
      // which must accumulate rather than be discarded.
      for (int i = 0; i < 4; i++) {
        final out = extractor.process(
          complexTone(0, sampleRate, 30),
          offsetHz: 0,
          sampleRate: sampleRate,
          decimation: 4,
        );
        total += out.length ~/ 2;
      }
      expect(total, (30 * 4) ~/ 4);
    });

    test('phase stays continuous across frame boundaries', () {
      // A split stream must demodulate identically to the same stream whole,
      // otherwise every frame edge is an audible click.
      const pairs = 512;
      final whole = complexTone(150000, sampleRate, pairs * 2);
      final continuous = ChannelExtractor().process(
        whole,
        offsetHz: 150000,
        sampleRate: sampleRate,
        decimation: 4,
      );

      final split = ChannelExtractor();
      final firstHalf = Float64List.sublistView(whole, 0, pairs * 2);
      final secondHalf = Float64List.sublistView(whole, pairs * 2);
      final a = split.process(firstHalf,
          offsetHz: 150000, sampleRate: sampleRate, decimation: 4);
      final b = split.process(secondHalf,
          offsetHz: 150000, sampleRate: sampleRate, decimation: 4);

      expect(a.length + b.length, continuous.length);
      for (int i = 0; i < b.length; i++) {
        expect(b[i], closeTo(continuous[a.length + i], 1e-6),
            reason: 'sample $i of the second frame diverged');
      }
    });

    test('reset clears carried state', () {
      final extractor = ChannelExtractor();
      extractor.process(complexTone(0, sampleRate, 30),
          offsetHz: 0, sampleRate: sampleRate, decimation: 4);
      extractor.reset();
      // With no carry-over, 8 samples at decimation 4 gives exactly 2 pairs.
      final out = extractor.process(complexTone(0, sampleRate, 8),
          offsetHz: 0, sampleRate: sampleRate, decimation: 4);
      expect(out.length ~/ 2, 2);
    });

    test('rejects a nonsensical decimation factor', () {
      final out = ChannelExtractor().process(
        complexTone(0, sampleRate, 64),
        offsetHz: 0,
        sampleRate: sampleRate,
        decimation: 0,
      );
      expect(out, isEmpty);
    });
  });
}
