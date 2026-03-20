class FrequencyFormatter {
  /// Formats a frequency in Hz to a human-readable string with appropriate units.
  ///
  /// [hz] The frequency in Hertz.
  /// [precision] The number of decimal places to show. If null, it defaults to
  /// 0 for Hz, and 1 or more for larger units based on the value.
  /// [shortUnit] If true, uses short unit names (Hz, k, M, G) and no space.
  /// If false, uses full names (Hz, kHz, MHz, GHz) with a space.
  static String format(double hz, {int? precision, bool shortUnit = false}) {
    final double absHz = hz.abs();
    String unit;
    double value;

    if (absHz >= 999999500) { // 999.9995 MHz -> 1 GHz
      value = hz / 1e9;
      unit = shortUnit ? "G" : " GHz";
    } else if (absHz >= 999500) { // 999.5 kHz -> 1 MHz
      value = hz / 1e6;
      unit = shortUnit ? "M" : " MHz";
    } else if (absHz >= 995) { // 995 Hz -> 1 kHz
      value = hz / 1e3;
      unit = shortUnit ? "k" : " kHz";
    } else {
      value = hz;
      unit = shortUnit ? "Hz" : " Hz";
    }

    int p = precision ?? (absHz < 995 ? 0 : 1);
    return "${value.toStringAsFixed(p)}$unit";
  }
}
