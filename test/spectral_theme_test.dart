import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/core/spectral_theme.dart';

void main() {
  group('SpectralTheme', () {
    test('provides an accent and background for every theme', () {
      for (final theme in AppTheme.values) {
        expect(SpectralTheme.accent(theme), isA<Color>());
        expect(SpectralTheme.background(theme), isA<Color>());
      }
    });

    test('waterfall ramp covers the full range for every theme', () {
      for (final theme in AppTheme.values) {
        for (final v in [0.0, 0.25, 0.5, 0.75, 1.0, 1.1]) {
          expect(SpectralTheme.waterfallColor(theme, v), isA<Color>());
        }
      }
    });

    test('gray ramp goes from black to white', () {
      expect(SpectralTheme.waterfallColor(AppTheme.gray, 0.0), const Color(0xFF000000));
      expect(SpectralTheme.waterfallColor(AppTheme.gray, 1.0), const Color(0xFFFFFFFF));
    });

    test('ramp brightens with magnitude', () {
      // The low end of the frost ramp should be darker than the high end.
      final low = SpectralTheme.waterfallColor(AppTheme.frost, 0.1).computeLuminance();
      final high = SpectralTheme.waterfallColor(AppTheme.frost, 1.0).computeLuminance();
      expect(high, greaterThan(low));
    });
  });
}
