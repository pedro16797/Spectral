enum AppTheme {
  frost,
  magma,
  gray,
  emerald,
  rainbow,
}

enum SignalSourceType {
  audio,
  rf,
}

enum RfSourceType {
  integrated,
  mock,
  rtlTcp,
}

enum FftWindowType {
  hanning,
  hamming,
  blackman,
  bartlett,
}

enum FftAveragingMode {
  none,
  linear,
  exponential,
}

class AppSettings {
  final AppTheme theme;
  final SignalSourceType signalSource;
  final RfSourceType rfSource;
  final String rtlTcpHost;
  final int rtlTcpPort;
  final double centerFrequency; // MHz
  final double rfBandwidth; // MHz
  final int fftWindowSize;
  final FftWindowType fftWindowType;
  final String language;
  final double frequencySkew;
  final double fftSmoothing;
  final bool peakHoldEnabled;
  final FftAveragingMode fftAveragingMode;
  final int fftAveragingCount;
  final double ppmCorrection;
  final bool showHarmonics;
  final bool showSnr;

  const AppSettings({
    this.theme = AppTheme.frost,
    this.signalSource = SignalSourceType.audio,
    this.rfSource = RfSourceType.integrated,
    this.rtlTcpHost = '127.0.0.1',
    this.rtlTcpPort = 1234,
    this.centerFrequency = 100.0, // Default to 100 MHz (FM band center-ish)
    this.rfBandwidth = 2.0, // Default to 2 MHz
    this.fftWindowSize = 1024,
    this.fftWindowType = FftWindowType.hanning,
    this.language = 'en',
    this.frequencySkew = 1.0,
    this.fftSmoothing = 0.0,
    this.peakHoldEnabled = false,
    this.fftAveragingMode = FftAveragingMode.none,
    this.fftAveragingCount = 5,
    this.ppmCorrection = 0.0,
    this.showHarmonics = false,
    this.showSnr = false,
  });

  AppSettings copyWith({
    AppTheme? theme,
    SignalSourceType? signalSource,
    RfSourceType? rfSource,
    String? rtlTcpHost,
    int? rtlTcpPort,
    double? centerFrequency,
    double? rfBandwidth,
    int? fftWindowSize,
    FftWindowType? fftWindowType,
    String? language,
    double? frequencySkew,
    double? fftSmoothing,
    bool? peakHoldEnabled,
    FftAveragingMode? fftAveragingMode,
    int? fftAveragingCount,
    double? ppmCorrection,
    bool? showHarmonics,
    bool? showSnr,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      signalSource: signalSource ?? this.signalSource,
      rfSource: rfSource ?? this.rfSource,
      rtlTcpHost: rtlTcpHost ?? this.rtlTcpHost,
      rtlTcpPort: rtlTcpPort ?? this.rtlTcpPort,
      centerFrequency: centerFrequency ?? this.centerFrequency,
      rfBandwidth: rfBandwidth ?? this.rfBandwidth,
      fftWindowSize: fftWindowSize ?? this.fftWindowSize,
      fftWindowType: fftWindowType ?? this.fftWindowType,
      language: language ?? this.language,
      frequencySkew: frequencySkew ?? this.frequencySkew,
      fftSmoothing: fftSmoothing ?? this.fftSmoothing,
      peakHoldEnabled: peakHoldEnabled ?? this.peakHoldEnabled,
      fftAveragingMode: fftAveragingMode ?? this.fftAveragingMode,
      fftAveragingCount: fftAveragingCount ?? this.fftAveragingCount,
      ppmCorrection: ppmCorrection ?? this.ppmCorrection,
      showHarmonics: showHarmonics ?? this.showHarmonics,
      showSnr: showSnr ?? this.showSnr,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'theme': theme.name,
      'signalSource': signalSource.name,
      'rfSource': rfSource.name,
      'rtlTcpHost': rtlTcpHost,
      'rtlTcpPort': rtlTcpPort,
      'centerFrequency': centerFrequency,
      'rfBandwidth': rfBandwidth,
      'fftWindowSize': fftWindowSize,
      'fftWindowType': fftWindowType.name,
      'language': language,
      'frequencySkew': frequencySkew,
      'fftSmoothing': fftSmoothing,
      'peakHoldEnabled': peakHoldEnabled,
      'fftAveragingMode': fftAveragingMode.name,
      'fftAveragingCount': fftAveragingCount,
      'ppmCorrection': ppmCorrection,
      'showHarmonics': showHarmonics,
      'showSnr': showSnr,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      theme: AppTheme.values.firstWhere(
        (e) => e.name == map['theme'],
        orElse: () => AppTheme.frost,
      ),
      signalSource: SignalSourceType.values.firstWhere(
        (e) => e.name == (map['signalSource'] ?? 'audio'),
        orElse: () => SignalSourceType.audio,
      ),
      rfSource: RfSourceType.values.firstWhere(
        (e) => e.name == (map['rfSource'] ?? 'integrated'),
        orElse: () => RfSourceType.integrated,
      ),
      rtlTcpHost: map['rtlTcpHost'] ?? '127.0.0.1',
      rtlTcpPort: map['rtlTcpPort'] ?? 1234,
      centerFrequency: (map['centerFrequency'] ?? 100.0).toDouble(),
      rfBandwidth: (map['rfBandwidth'] ?? 2.0).toDouble(),
      fftWindowSize: map['fftWindowSize'] ?? 1024,
      fftWindowType: FftWindowType.values.firstWhere(
        (e) => e.name == map['fftWindowType'],
        orElse: () => FftWindowType.hanning,
      ),
      language: map['language'] ?? 'en',
      frequencySkew: (map['frequencySkew'] ?? 1.0).toDouble(),
      fftSmoothing: (map['fftSmoothing'] ?? 0.0).toDouble(),
      peakHoldEnabled: map['peakHoldEnabled'] ?? false,
      fftAveragingMode: FftAveragingMode.values.firstWhere(
        (e) => e.name == (map['fftAveragingMode'] ?? 'none'),
        orElse: () => FftAveragingMode.none,
      ),
      fftAveragingCount: map['fftAveragingCount'] ?? 5,
      ppmCorrection: (map['ppmCorrection'] ?? 0.0).toDouble(),
      showHarmonics: map['showHarmonics'] ?? false,
      showSnr: map['showSnr'] ?? false,
    );
  }
}
