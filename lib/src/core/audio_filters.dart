import 'dart:typed_data';

/// One-pole DC-blocking high-pass filter: `y[n] = x[n] - x[n-1] + R*y[n-1]`.
///
/// Removes the large DC component that AM envelope detection produces (the
/// envelope is strictly positive) and any residual offset from an FM
/// discriminator. [r] near 1.0 gives a very low cutoff (≈ `(1-r) * fs / 2π`).
class DcBlocker {
  final double _r;
  double _x1 = 0.0;
  double _y1 = 0.0;

  DcBlocker({double r = 0.999}) : _r = r;

  double processSample(double x) {
    final double y = x - _x1 + _r * _y1;
    _x1 = x;
    _y1 = y;
    return y;
  }

  void processInPlace(Float64List buffer) {
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = processSample(buffer[i]);
    }
  }

  void reset() {
    _x1 = 0.0;
    _y1 = 0.0;
  }
}

/// One-pole low-pass de-emphasis filter for FM broadcast audio:
/// `y[n] = y[n-1] + alpha*(x[n] - y[n-1])`, with `alpha = dt / (tau + dt)`.
///
/// FM broadcast pre-emphasizes high frequencies at the transmitter; the
/// receiver must apply the matching de-emphasis (75 µs in the Americas/Korea,
/// 50 µs elsewhere) or the audio sounds harsh/hissy.
class Deemphasis {
  double _alpha;
  double _y1 = 0.0;

  Deemphasis({required double sampleRate, double tauSeconds = 75e-6})
      : _alpha = _computeAlpha(sampleRate, tauSeconds);

  static double _computeAlpha(double sampleRate, double tau) {
    if (sampleRate <= 0) return 1.0;
    final double dt = 1.0 / sampleRate;
    return dt / (tau + dt);
  }

  /// Recomputes the coefficient for a new [sampleRate] (e.g. after the SDR
  /// bandwidth changes). Does not reset filter state.
  void configure({required double sampleRate, double tauSeconds = 75e-6}) {
    _alpha = _computeAlpha(sampleRate, tauSeconds);
  }

  double processSample(double x) {
    _y1 += _alpha * (x - _y1);
    return _y1;
  }

  void processInPlace(Float64List buffer) {
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = processSample(buffer[i]);
    }
  }

  void reset() {
    _y1 = 0.0;
  }
}

/// Streaming linear-interpolation resampler.
///
/// Converts audio from one sample rate to another while preserving phase
/// across chunk boundaries (the last input sample is carried over so the next
/// chunk can interpolate against it). Linear interpolation alone does not
/// anti-alias, so for large downsampling ratios run an averaged integer
/// decimation first and use this only for the fractional remainder.
class LinearResampler {
  /// Input samples consumed per output sample.
  double _ratio = 1.0;

  /// Fractional read position, relative to the current chunk's first sample.
  /// A value in (-1, 0) points between the carried previous sample and the
  /// chunk's first sample.
  double _pos = 0.0;

  double _prev = 0.0;
  bool _hasPrev = false;

  void configure({required double inputRate, required double outputRate}) {
    _ratio = (inputRate > 0 && outputRate > 0) ? inputRate / outputRate : 1.0;
  }

  void reset() {
    _pos = 0.0;
    _prev = 0.0;
    _hasPrev = false;
  }

  Float64List process(Float64List input) {
    if (input.isEmpty) return input;

    final int capacity = (input.length / _ratio).ceil() + 2;
    final out = Float64List(capacity);
    int produced = 0;
    double pos = _pos;

    while (pos <= input.length - 1) {
      double value;
      if (pos < 0) {
        final double t = pos + 1;
        value = _hasPrev ? _prev + (input[0] - _prev) * t : input[0];
      } else {
        final int i = pos.floor();
        final double t = pos - i;
        value = (i + 1 < input.length)
            ? input[i] + (input[i + 1] - input[i]) * t
            : input[i];
      }
      out[produced++] = value;
      pos += _ratio;
    }

    _pos = pos - input.length;
    _prev = input.last;
    _hasPrev = true;
    return Float64List.sublistView(out, 0, produced);
  }
}
