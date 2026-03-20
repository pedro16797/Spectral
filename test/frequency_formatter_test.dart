import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/utils/frequency_formatter.dart';

void main() {
  group('FrequencyFormatter', () {
    test('formats Hz correctly', () {
      expect(FrequencyFormatter.format(500), '500 Hz');
      expect(FrequencyFormatter.format(500, shortUnit: true), '500Hz');
    });

    test('formats kHz correctly', () {
      expect(FrequencyFormatter.format(1500), '1.5 kHz');
      expect(FrequencyFormatter.format(1500, shortUnit: true), '1.5k');
      expect(FrequencyFormatter.format(1000, precision: 0), '1 kHz');
    });

    test('formats MHz correctly', () {
      expect(FrequencyFormatter.format(100.5e6), '100.5 MHz');
      expect(FrequencyFormatter.format(100.5e6, shortUnit: true), '100.5M');
      expect(FrequencyFormatter.format(100e6, precision: 3), '100.000 MHz');
    });

    test('formats GHz correctly', () {
      expect(FrequencyFormatter.format(2.4e9), '2.4 GHz');
      expect(FrequencyFormatter.format(2.4e9, shortUnit: true), '2.4G');
    });

    test('handles rounding at unit boundaries', () {
      // 999.5 Hz should be 1.0 kHz
      expect(FrequencyFormatter.format(999.5), '1.0 kHz');
      // 994 Hz should be 994 Hz
      expect(FrequencyFormatter.format(994), '994 Hz');

      // 999,500 Hz should be 1.0 MHz
      expect(FrequencyFormatter.format(999500), '1.0 MHz');

      // 999,999,500 Hz should be 1.0 GHz
      expect(FrequencyFormatter.format(999999500), '1.0 GHz');
    });

    test('handles zero and negative frequencies', () {
      expect(FrequencyFormatter.format(0), '0 Hz');
      expect(FrequencyFormatter.format(-1000), '-1.0 kHz');
    });
  });
}
