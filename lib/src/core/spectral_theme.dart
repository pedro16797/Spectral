import 'package:flutter/material.dart';
import 'settings_model.dart';

/// Centralized visual identity for each [AppTheme]: the accent color, the
/// background base color, and the waterfall magnitude→color ramp.
class SpectralTheme {
  const SpectralTheme._();

  /// Elevated surface color shared by dialogs, dropdowns, and the app's
  /// color scheme.
  static const Color surface = Color(0xFF1C1C1E);

  /// Slightly lighter surface used for floating overlays such as tooltips.
  static const Color surfaceLight = Color(0xFF2C2C2E);

  /// Primary accent color used for highlights, active controls, and the FFT.
  static Color accent(AppTheme theme) {
    switch (theme) {
      case AppTheme.frost:
        return const Color(0xFF007AFF);
      case AppTheme.magma:
        return Colors.orangeAccent;
      case AppTheme.gray:
        return Colors.white;
      case AppTheme.emerald:
        return const Color(0xFF00C853);
      case AppTheme.rainbow:
        return Colors.purpleAccent;
    }
  }

  /// Base color for the radial background gradient.
  static Color background(AppTheme theme) {
    switch (theme) {
      case AppTheme.frost:
        return const Color(0xFF001A33);
      case AppTheme.magma:
        return const Color(0xFF330D00);
      case AppTheme.gray:
        return const Color(0xFF1A1A1A);
      case AppTheme.emerald:
        return const Color(0xFF001A00);
      case AppTheme.rainbow:
        return const Color(0xFF100010);
    }
  }

  /// Maps a normalized magnitude to a color on the theme's waterfall ramp.
  /// Input is clamped to [0, 1]; the ramps are only defined on that range.
  static Color waterfallColor(AppTheme theme, double value) {
    value = value.clamp(0.0, 1.0);
    switch (theme) {
      case AppTheme.frost:
        return _frost(value);
      case AppTheme.magma:
        return _magma(value);
      case AppTheme.gray:
        return _gray(value);
      case AppTheme.emerald:
        return _emerald(value);
      case AppTheme.rainbow:
        return _rainbow(value);
    }
  }

  static Color _frost(double value) {
    if (value < 0.3) {
      return Color.lerp(const Color(0xFF001A33), const Color(0xFF007AFF), value / 0.3)!;
    } else if (value < 0.7) {
      return Color.lerp(const Color(0xFF007AFF), const Color(0xFF5AC8FA), (value - 0.3) / 0.4)!;
    } else {
      return Color.lerp(const Color(0xFF5AC8FA), Colors.white, (value - 0.7) / 0.3)!;
    }
  }

  static Color _magma(double value) {
    if (value < 0.2) {
      return Color.lerp(const Color(0xFF000000), const Color(0xFF7D0000), value / 0.2)!;
    } else if (value < 0.5) {
      return Color.lerp(const Color(0xFF7D0000), const Color(0xFFFF4500), (value - 0.2) / 0.3)!;
    } else if (value < 0.8) {
      return Color.lerp(const Color(0xFFFF4500), const Color(0xFFFFD700), (value - 0.5) / 0.3)!;
    } else {
      return Color.lerp(const Color(0xFFFFD700), Colors.white, (value - 0.8) / 0.2)!;
    }
  }

  static Color _gray(double value) {
    return Color.lerp(Colors.black, Colors.white, value)!;
  }

  static Color _emerald(double value) {
    if (value < 0.3) {
      return Color.lerp(const Color(0xFF001A00), const Color(0xFF00C853), value / 0.3)!;
    } else if (value < 0.7) {
      return Color.lerp(const Color(0xFF00C853), const Color(0xFF69F0AE), (value - 0.3) / 0.4)!;
    } else {
      return Color.lerp(const Color(0xFF69F0AE), Colors.white, (value - 0.7) / 0.3)!;
    }
  }

  static Color _rainbow(double value) {
    // Black -> Purple -> Blue -> Cyan -> Green -> Yellow -> Red -> White
    if (value < 0.1) {
      return Color.lerp(Colors.black, Colors.purple, value / 0.1)!;
    } else if (value < 0.25) {
      return Color.lerp(Colors.purple, Colors.blue, (value - 0.1) / 0.15)!;
    } else if (value < 0.4) {
      return Color.lerp(Colors.blue, Colors.cyan, (value - 0.25) / 0.15)!;
    } else if (value < 0.55) {
      return Color.lerp(Colors.cyan, Colors.green, (value - 0.4) / 0.15)!;
    } else if (value < 0.7) {
      return Color.lerp(Colors.green, Colors.yellow, (value - 0.55) / 0.15)!;
    } else if (value < 0.85) {
      return Color.lerp(Colors.yellow, Colors.red, (value - 0.7) / 0.15)!;
    } else {
      return Color.lerp(Colors.red, Colors.white, (value - 0.85) / 0.15)!;
    }
  }
}
