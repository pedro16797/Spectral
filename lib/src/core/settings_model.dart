enum AppTheme {
  liquidBlue,
  inferno,
  monochrome,
  emerald,
  rainbow,
}

enum FftWindowType {
  hanning,
  hamming,
  blackman,
  bartlett,
}

class AppSettings {
  final AppTheme theme;
  final int fftWindowSize;
  final FftWindowType fftWindowType;
  final String language;
  final double frequencySkew;
  final double fftSmoothing;

  const AppSettings({
    this.theme = AppTheme.liquidBlue,
    this.fftWindowSize = 1024,
    this.fftWindowType = FftWindowType.hanning,
    this.language = 'en',
    this.frequencySkew = 1.0,
    this.fftSmoothing = 0.0,
  });

  AppSettings copyWith({
    AppTheme? theme,
    int? fftWindowSize,
    FftWindowType? fftWindowType,
    String? language,
    double? frequencySkew,
    double? fftSmoothing,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      fftWindowSize: fftWindowSize ?? this.fftWindowSize,
      fftWindowType: fftWindowType ?? this.fftWindowType,
      language: language ?? this.language,
      frequencySkew: frequencySkew ?? this.frequencySkew,
      fftSmoothing: fftSmoothing ?? this.fftSmoothing,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'theme': theme.name,
      'fftWindowSize': fftWindowSize,
      'fftWindowType': fftWindowType.name,
      'language': language,
      'frequencySkew': frequencySkew,
      'fftSmoothing': fftSmoothing,
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
      frequencySkew: (map['frequencySkew'] ?? 1.0).toDouble(),
      fftSmoothing: (map['fftSmoothing'] ?? 0.0).toDouble(),
    );
  }
}
