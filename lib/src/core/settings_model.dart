enum AppTheme {
  liquidBlue,
  inferno,
  monochrome,
  emerald,
}

enum FftWindowType {
  hanning,
  hamming,
  blackman,
}

class AppSettings {
  final AppTheme theme;
  final int fftWindowSize;
  final FftWindowType fftWindowType;
  final String language;

  const AppSettings({
    this.theme = AppTheme.liquidBlue,
    this.fftWindowSize = 1024,
    this.fftWindowType = FftWindowType.hanning,
    this.language = 'en',
  });

  AppSettings copyWith({
    AppTheme? theme,
    int? fftWindowSize,
    FftWindowType? fftWindowType,
    String? language,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      fftWindowSize: fftWindowSize ?? this.fftWindowSize,
      fftWindowType: fftWindowType ?? this.fftWindowType,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'theme': theme.name,
      'fftWindowSize': fftWindowSize,
      'fftWindowType': fftWindowType.name,
      'language': language,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      theme: AppTheme.values.firstWhere(
        (e) => e.name == map['theme'],
        orElse: () => AppTheme.liquidBlue,
      ),
      fftWindowSize: map['fftWindowSize'] ?? 1024,
      fftWindowType: FftWindowType.values.firstWhere(
        (e) => e.name == map['fftWindowType'],
        orElse: () => FftWindowType.hanning,
      ),
      language: map['language'] ?? 'en',
    );
  }
}
