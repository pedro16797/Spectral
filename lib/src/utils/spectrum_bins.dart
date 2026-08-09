import 'dart:math' as math;
import 'dart:typed_data';

import 'frequency_scale.dart';

/// Compresses a raw FFT magnitude into [0, 1] for display.
///
/// Shared by the spectrum painters so the bar chart and the waterfall render
/// the same signal at the same intensity.
double normalizeMagnitude(double magnitude) =>
    (math.log(magnitude + 1) / 4.5).clamp(0.0, 1.0);

/// Maps display columns onto FFT bins for the spectrum and waterfall painters.
///
/// Two things this gets right that a naive `frequency / nyquist` mapping does
/// not:
///
/// **The FFT does not always start at 0 Hz.** A real (audio) FFT spans
/// 0..Nyquist, but a complex RF spectrum is centred on the tuned frequency and
/// spans `centre ± sampleRate/2`. Normalising an absolute RF frequency against
/// Nyquist alone produces a value far outside [0, 1], which clamps every
/// column onto the same bin — a flat, featureless display.
///
/// **There are far more bins than columns.** A 1024-point FFT drawn into ~150
/// columns covers ~7 bins per column, and picking one of them at random misses
/// narrow carriers entirely. Taking the peak across the covered bins is what
/// makes signals actually appear, and it is why a larger FFT then helps rather
/// than hurts.
class SpectrumBinMapper {
  /// Fractional positions (0..1) of each column edge within the FFT array.
  /// Stored as fractions rather than indices so a single mapper still works
  /// across history rows captured at a different window size.
  final Float64List _edges;

  final int columnCount;

  /// [viewStartHz]..[viewEndHz] is the visible window; [bandStartHz]..
  /// [bandEndHz] is the full span the FFT data covers.
  SpectrumBinMapper({
    required this.columnCount,
    required double viewStartHz,
    required double viewEndHz,
    required double bandStartHz,
    required double bandEndHz,
    required double frequencySkew,
  }) : _edges = Float64List(columnCount + 1) {
    final double bandSpan = bandEndHz - bandStartHz;
    if (bandSpan <= 0) return;

    final double start = (viewStartHz - bandStartHz) / bandSpan;
    final double end = (viewEndHz - bandStartHz) / bandSpan;
    final double range = end - start;

    for (int i = 0; i <= columnCount; i++) {
      // The skew curve spreads columns non-uniformly across the window.
      final double t = FrequencyScale.toData(i / columnCount, frequencySkew);
      _edges[i] = (start + t * range).clamp(0.0, 1.0);
    }
  }

  /// Highest magnitude among the bins that [column] covers.
  ///
  /// Returns 0 for an empty or out-of-range request rather than throwing —
  /// this runs inside paint, where a stale history row is normal.
  double peak(List<double> data, int column) {
    if (data.isEmpty || column < 0 || column >= columnCount) return 0;

    final int length = data.length;
    int start = (_edges[column] * length).floor();
    int end = (_edges[column + 1] * length).ceil();

    if (start < 0) start = 0;
    if (start > length - 1) start = length - 1;
    // Always cover at least one bin, even where the window is so zoomed in
    // that several columns land inside a single bin.
    if (end <= start) end = start + 1;
    if (end > length) end = length;

    double best = 0;
    for (int b = start; b < end; b++) {
      final double v = data[b];
      if (v > best) best = v;
    }
    return best;
  }
}
