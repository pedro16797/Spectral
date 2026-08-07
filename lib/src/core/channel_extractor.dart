import 'dart:math' as math;
import 'dart:typed_data';

/// Extracts one narrow channel out of a wideband complex I/Q stream.
///
/// This is how an SDR tunes *inside* the band it already captured, without
/// retuning the hardware: mix the wanted channel down to DC with a numerically
/// controlled oscillator, then average-and-decimate down to that channel's own
/// sample rate.
///
/// The averaging doubles as the anti-alias filter. A boxcar of length N has its
/// nulls at exact multiples of the decimated rate — precisely the frequencies
/// that would otherwise fold onto the signal — so it is a much better fit here
/// than its flat-ish passband suggests.
///
/// Decimating first also moves the expensive per-sample demodulation
/// (`atan2` for FM) from the full capture rate down to the channel rate, which
/// for a 200 kHz channel out of 2.4 MS/s is an order of magnitude less work.
class ChannelExtractor {
  /// Numerically controlled oscillator, held as a unit vector that gets
  /// rotated by a fixed step per sample. Cheaper than calling sin/cos per
  /// sample, and it keeps phase continuous across frames — which matters,
  /// because a phase discontinuity is a click in the demodulated audio.
  double _oscI = 1.0;
  double _oscQ = 0.0;

  /// Samples since the oscillator was last renormalized. Repeated rotation
  /// slowly drifts off the unit circle, so it is rescaled periodically.
  int _sinceRenormalize = 0;
  static const int _renormalizeInterval = 1024;

  /// Partial decimation accumulator, carried across frames so that sample
  /// groups never get split or dropped at a frame boundary.
  double _accI = 0.0;
  double _accQ = 0.0;
  int _accCount = 0;

  /// Decimation the carried accumulator belongs to. Retuning can shrink the
  /// factor below the samples already banked, which would strand them.
  int _accDecimation = 0;

  /// Resets oscillator and accumulator state. Call when the stream restarts.
  void reset() {
    _oscI = 1.0;
    _oscQ = 0.0;
    _sinceRenormalize = 0;
    _discardAccumulator();
  }

  void _discardAccumulator() {
    _accI = 0.0;
    _accQ = 0.0;
    _accCount = 0;
  }

  /// Number of output I/Q pairs [process] would produce for [inputPairs],
  /// given the accumulator state carried in from previous frames.
  int _outputPairsFor(int inputPairs, int decimation) =>
      (inputPairs + _accCount) ~/ decimation;

  /// Mixes [iq] — interleaved I/Q sampled at [sampleRate] — down by
  /// [offsetHz], then decimates by [decimation].
  ///
  /// Returns interleaved I/Q at `sampleRate / decimation`. A positive
  /// [offsetHz] selects a channel *above* the centre of [iq].
  Float64List process(
    Float64List iq, {
    required double offsetHz,
    required double sampleRate,
    required int decimation,
  }) {
    if (decimation < 1 || sampleRate <= 0) return Float64List(0);

    // Dragging the slider can change the decimation factor mid-stream. A part
    // group banked under the old factor is meaningless under the new one — and
    // if the factor shrank below the banked count it would never complete — so
    // drop it. At most one output sample is affected.
    if (decimation != _accDecimation) {
      _discardAccumulator();
      _accDecimation = decimation;
    }

    final int pairs = iq.length ~/ 2;
    final int outPairs = _outputPairsFor(pairs, decimation);
    final out = Float64List(outPairs * 2);
    if (pairs == 0) return out;

    // Rotation per sample for a shift of -offsetHz.
    final double phaseStep = -2 * math.pi * offsetHz / sampleRate;
    final double stepI = math.cos(phaseStep);
    final double stepQ = math.sin(phaseStep);

    double oscI = _oscI;
    double oscQ = _oscQ;
    double accI = _accI;
    double accQ = _accQ;
    int accCount = _accCount;
    int o = 0;

    for (int n = 0; n < pairs; n++) {
      final double i = iq[n * 2];
      final double q = iq[n * 2 + 1];

      // Complex multiply by the oscillator: the frequency shift itself.
      accI += i * oscI - q * oscQ;
      accQ += i * oscQ + q * oscI;
      accCount++;

      if (accCount >= decimation) {
        out[o++] = accI / decimation;
        out[o++] = accQ / decimation;
        accI = 0.0;
        accQ = 0.0;
        accCount = 0;
      }

      // Advance the oscillator by one step.
      final double nextI = oscI * stepI - oscQ * stepQ;
      final double nextQ = oscI * stepQ + oscQ * stepI;
      oscI = nextI;
      oscQ = nextQ;

      if (++_sinceRenormalize >= _renormalizeInterval) {
        _sinceRenormalize = 0;
        final double mag = math.sqrt(oscI * oscI + oscQ * oscQ);
        if (mag > 0) {
          oscI /= mag;
          oscQ /= mag;
        }
      }
    }

    _oscI = oscI;
    _oscQ = oscQ;
    _accI = accI;
    _accQ = accQ;
    _accCount = accCount;
    return out;
  }
}

/// How to reach a requested channel from within a captured band.
class ChannelPlan {
  const ChannelPlan({required this.offsetHz, required this.decimation});

  /// Distance from the capture centre to the channel centre. Positive means
  /// the channel sits above the centre frequency.
  final double offsetHz;

  /// Decimation factor from the capture rate down to the channel rate.
  final int decimation;

  bool get isPassthrough => decimation == 1 && offsetHz == 0;

  @override
  bool operator ==(Object other) =>
      other is ChannelPlan &&
      other.offsetHz == offsetHz &&
      other.decimation == decimation;

  @override
  int get hashCode => Object.hash(offsetHz, decimation);
}

/// Lowest channel rate worth producing. Below this there is not enough
/// bandwidth left to carry audio once demodulated.
const double kMinChannelBandwidthHz = 48000.0;

/// Works out how to extract the band [startHz]..[endHz] from a capture of
/// [captureRateHz] centred on [centerHz].
///
/// The requested width is widened to [kMinChannelBandwidthHz] if needed, and
/// the offset is clamped so the channel stays inside the captured band — a
/// selection outside it has no signal to give.
ChannelPlan planChannel({
  required double startHz,
  required double endHz,
  required double centerHz,
  required double captureRateHz,
}) {
  if (captureRateHz <= 0) {
    return const ChannelPlan(offsetHz: 0, decimation: 1);
  }

  final double lo = math.min(startHz, endHz);
  final double hi = math.max(startHz, endHz);
  final double width = math.max(hi - lo, kMinChannelBandwidthHz);

  // Never decimate below the requested width; floor() keeps the channel at
  // least as wide as asked for.
  final int decimation = (captureRateHz / width).floor().clamp(1, 1024);
  final double channelRate = captureRateHz / decimation;

  // Keep the whole channel inside the capture, so the edges are real signal
  // rather than wrap-around.
  final double halfRoom = math.max(0, (captureRateHz - channelRate) / 2);
  final double rawOffset = (lo + hi) / 2 - centerHz;
  final double offset = rawOffset.clamp(-halfRoom, halfRoom);

  return ChannelPlan(offsetHz: offset, decimation: decimation);
}
