import 'dart:math' as math;

/// Maps between normalized screen position and normalized frequency position
/// under a power-law skew, used to zoom/emphasize parts of the spectrum.
///
/// Both inputs and outputs are in the range [0, 1]. A [skew] of 1.0 is linear
/// (identity).
class FrequencyScale {
  const FrequencyScale._();

  /// Maps a normalized screen position [t] (0 = left, 1 = right) to a
  /// normalized frequency/data position.
  static double toData(double t, double skew) {
    if (skew == 1.0) return t;
    return math.pow(t, skew).toDouble();
  }

  /// Maps a normalized frequency/data position [t] back to a normalized screen
  /// position. Inverse of [toData].
  static double toScreen(double t, double skew) {
    if (skew == 1.0) return t;
    return math.pow(t, 1.0 / skew).toDouble();
  }
}
