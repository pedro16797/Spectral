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
    );
  }
}
