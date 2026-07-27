import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/utils/spectrum_bins.dart';

/// An FFT array with a single strong bin, everything else at the noise floor.
List<double> spikeAt(int index, int length, {double peak = 100, double floor = 1}) {
  final data = List<double>.filled(length, floor);
  data[index] = peak;
  return data;
}

void main() {
  group('audio spectrum (real FFT, 0..Nyquist)', () {
    test('spans the whole array when the view is the whole band', () {
      final mapper = SpectrumBinMapper(
        columnCount: 4,
        viewStartHz: 0,
        viewEndHz: 22050,
        bandStartHz: 0,
        bandEndHz: 22050,
        frequencySkew: 1.0,
      );
      final data = List<double>.generate(8, (i) => i.toDouble());
      // Ascending data: each column's peak must rise across the display.
      expect(mapper.peak(data, 0), lessThan(mapper.peak(data, 3)));
      expect(mapper.peak(data, 3), 7.0);
    });

    test('zooming to the upper half reads the upper half', () {
      final mapper = SpectrumBinMapper(
        columnCount: 2,
        viewStartHz: 11025,
        viewEndHz: 22050,
        bandStartHz: 0,
        bandEndHz: 22050,
        frequencySkew: 1.0,
      );
      // Spike in the lower half must not appear.
      expect(mapper.peak(spikeAt(1, 16), 0), 1.0);
      expect(mapper.peak(spikeAt(1, 16), 1), 1.0);
      // Spike in the upper half must.
      expect(mapper.peak(spikeAt(12, 16), 0), 100.0);
    });
  });

  group('RF spectrum (complex FFT, centre +/- rate/2)', () {
    // 2.4 MS/s centred on 100 MHz: the band runs 98.8..101.2 MHz.
    const bandStart = 98.8e6;
    const bandEnd = 101.2e6;

    test('absolute RF frequencies do not collapse onto one bin', () {
      // The regression this guards: normalising an absolute RF frequency
      // against Nyquist alone gives ~82, which clamps every column to the last
      // bin and paints a flat, featureless display.
      final mapper = SpectrumBinMapper(
        columnCount: 8,
        viewStartHz: bandStart,
        viewEndHz: bandEnd,
        bandStartHz: bandStart,
        bandEndHz: bandEnd,
        frequencySkew: 1.0,
      );
      final data = List<double>.generate(64, (i) => i.toDouble());
      final peaks = [for (int c = 0; c < 8; c++) mapper.peak(data, c)];
      expect(peaks.toSet().length, greaterThan(1),
          reason: 'every column resolved to the same bin');
      // And they must ascend with the ascending data.
      for (int c = 1; c < peaks.length; c++) {
        expect(peaks[c], greaterThan(peaks[c - 1]));
      }
    });

    test('a station below centre lands in the lower half of the display', () {
      final mapper = SpectrumBinMapper(
        columnCount: 10,
        viewStartHz: bandStart,
        viewEndHz: bandEnd,
        bandStartHz: bandStart,
        bandEndHz: bandEnd,
        frequencySkew: 1.0,
      );
      // A complex FFT is shifted so bin 0 is the bottom of the band. A spike a
      // quarter of the way up the array is a quarter of the way up the screen.
      final data = spikeAt(16, 64);
      final hot = [for (int c = 0; c < 10; c++) mapper.peak(data, c)]
          .indexWhere((v) => v == 100.0);
      expect(hot, inInclusiveRange(1, 3));
    });

    test('zooming onto one station excludes its neighbour', () {
      // View the upper quarter of the band only.
      final mapper = SpectrumBinMapper(
        columnCount: 4,
        viewStartHz: 100.6e6,
        viewEndHz: 101.2e6,
        bandStartHz: bandStart,
        bandEndHz: bandEnd,
        frequencySkew: 1.0,
      );
      // Spike near the bottom of the band is outside the zoomed view.
      expect(
        [for (int c = 0; c < 4; c++) mapper.peak(spikeAt(4, 64), c)],
        everyElement(1.0),
      );
      // Spike near the top is inside it.
      expect(
        [for (int c = 0; c < 4; c++) mapper.peak(spikeAt(60, 64), c)],
        contains(100.0),
      );
    });
  });

  group('peak aggregation', () {
    test('a narrow carrier survives being drawn into fewer columns', () {
      // 1024 bins into 160 columns: point-sampling would skip ~6 bins in 7.
      final mapper = SpectrumBinMapper(
        columnCount: 160,
        viewStartHz: 0,
        viewEndHz: 1,
        bandStartHz: 0,
        bandEndHz: 1,
        frequencySkew: 1.0,
      );
      // Every single-bin spike must be visible somewhere on the display.
      for (final bin in [3, 137, 511, 900, 1023]) {
        final data = spikeAt(bin, 1024);
        final found =
            [for (int c = 0; c < 160; c++) mapper.peak(data, c)].contains(100.0);
        expect(found, isTrue, reason: 'spike at bin $bin was dropped');
      }
    });

    test('covers every bin exactly once across the display', () {
      final mapper = SpectrumBinMapper(
        columnCount: 16,
        viewStartHz: 0,
        viewEndHz: 1,
        bandStartHz: 0,
        bandEndHz: 1,
        frequencySkew: 1.0,
      );
      // Each bin, spiked in isolation, must show up in some column.
      for (int bin = 0; bin < 64; bin++) {
        final data = spikeAt(bin, 64);
        final found =
            [for (int c = 0; c < 16; c++) mapper.peak(data, c)].contains(100.0);
        expect(found, isTrue, reason: 'bin $bin is not covered by any column');
      }
    });

    test('more columns than bins still resolves each column', () {
      final mapper = SpectrumBinMapper(
        columnCount: 32,
        viewStartHz: 0,
        viewEndHz: 1,
        bandStartHz: 0,
        bandEndHz: 1,
        frequencySkew: 1.0,
      );
      final data = List<double>.filled(8, 5.0);
      for (int c = 0; c < 32; c++) {
        expect(mapper.peak(data, c), 5.0);
      }
    });
  });

  group('robustness', () {
    final mapper = SpectrumBinMapper(
      columnCount: 4,
      viewStartHz: 0,
      viewEndHz: 1,
      bandStartHz: 0,
      bandEndHz: 1,
      frequencySkew: 1.0,
    );

    test('empty data and out-of-range columns return zero', () {
      expect(mapper.peak(const [], 0), 0);
      expect(mapper.peak(const [1, 2, 3], -1), 0);
      expect(mapper.peak(const [1, 2, 3], 99), 0);
    });

    test('history rows of a different length are still mapped', () {
      // Window size can change mid-session, leaving shorter rows in history.
      expect(mapper.peak(List<double>.filled(4, 2.0), 3), 2.0);
      expect(mapper.peak(List<double>.filled(4096, 2.0), 3), 2.0);
    });

    test('a degenerate band does not throw', () {
      final flat = SpectrumBinMapper(
        columnCount: 4,
        viewStartHz: 100,
        viewEndHz: 200,
        bandStartHz: 50,
        bandEndHz: 50,
        frequencySkew: 1.0,
      );
      expect(flat.peak(List<double>.filled(8, 3.0), 0), 3.0);
    });
  });
}
