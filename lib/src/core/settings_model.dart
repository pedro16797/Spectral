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

/// What the spectrum, waterfall and analysis readouts represent.
///
/// Only meaningful for a complex (SDR) source, where there are two genuinely
/// different signals to look at: the radio band itself, or the audio recovered
/// from the tuned channel.
enum SpectrumView {
  /// The captured RF band — the map used to find and tune stations.
  rf,

  /// The demodulated audio, so tone detection, harmonics and SNR describe the
  /// recovered programme rather than the radio spectrum.
  demodulated,
}

enum DemodulationMode {
  none,
  am,
  fm,
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
  final bool peakHoldEnabled;
  final FftAveragingMode fftAveragingMode;
  final int fftAveragingCount;
  final double ppmCorrection;
  final bool showHarmonics;
  final bool showSnr;
  final DemodulationMode demodulationMode;
  final bool audioOutputEnabled;
  final SpectrumView spectrumView;

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
    this.peakHoldEnabled = false,
    this.fftAveragingMode = FftAveragingMode.none,
    this.fftAveragingCount = 5,
    this.ppmCorrection = 0.0,
    this.showHarmonics = false,
    this.showSnr = false,
    this.demodulationMode = DemodulationMode.none,
    this.audioOutputEnabled = false,
    this.spectrumView = SpectrumView.rf,
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
    bool? peakHoldEnabled,
    FftAveragingMode? fftAveragingMode,
    int? fftAveragingCount,
    double? ppmCorrection,
    bool? showHarmonics,
    bool? showSnr,
    DemodulationMode? demodulationMode,
    bool? audioOutputEnabled,
    SpectrumView? spectrumView,
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
      peakHoldEnabled: peakHoldEnabled ?? this.peakHoldEnabled,
      fftAveragingMode: fftAveragingMode ?? this.fftAveragingMode,
      fftAveragingCount: fftAveragingCount ?? this.fftAveragingCount,
      ppmCorrection: ppmCorrection ?? this.ppmCorrection,
      showHarmonics: showHarmonics ?? this.showHarmonics,
      showSnr: showSnr ?? this.showSnr,
      demodulationMode: demodulationMode ?? this.demodulationMode,
      audioOutputEnabled: audioOutputEnabled ?? this.audioOutputEnabled,
      spectrumView: spectrumView ?? this.spectrumView,
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
      'peakHoldEnabled': peakHoldEnabled,
      'fftAveragingMode': fftAveragingMode.name,
      'fftAveragingCount': fftAveragingCount,
      'ppmCorrection': ppmCorrection,
      'showHarmonics': showHarmonics,
      'showSnr': showSnr,
      'demodulationMode': demodulationMode.name,
      'audioOutputEnabled': audioOutputEnabled,
      'spectrumView': spectrumView.name,
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
      rtlTcpHost: _asString(map['rtlTcpHost'], '127.0.0.1'),
      rtlTcpPort: _asInt(map['rtlTcpPort'], 1234),
      centerFrequency: _asDouble(map['centerFrequency'], 100.0),
      rfBandwidth: _asDouble(map['rfBandwidth'], 2.0),
      fftWindowSize: _asInt(map['fftWindowSize'], 1024),
      fftWindowType: FftWindowType.values.firstWhere(
        (e) => e.name == map['fftWindowType'],
        orElse: () => FftWindowType.hanning,
      ),
      language: _asString(map['language'], 'en'),
      frequencySkew: _asDouble(map['frequencySkew'], 1.0),
      peakHoldEnabled: _asBool(map['peakHoldEnabled'], false),
      fftAveragingMode: FftAveragingMode.values.firstWhere(
        (e) => e.name == (map['fftAveragingMode'] ?? 'none'),
        orElse: () => FftAveragingMode.none,
      ),
      fftAveragingCount: _asInt(map['fftAveragingCount'], 5),
      ppmCorrection: _asDouble(map['ppmCorrection'], 0.0),
      showHarmonics: _asBool(map['showHarmonics'], false),
      showSnr: _asBool(map['showSnr'], false),
      demodulationMode: DemodulationMode.values.firstWhere(
        (e) => e.name == (map['demodulationMode'] ?? 'none'),
        orElse: () => DemodulationMode.none,
      ),
      audioOutputEnabled: _asBool(map['audioOutputEnabled'], false),
      spectrumView: SpectrumView.values.firstWhere(
        (e) => e.name == (map['spectrumView'] ?? 'rf'),
        orElse: () => SpectrumView.rf,
      ),
    );
  }
}

// ---- Lenient coercion helpers for AppSettings.fromMap ----
// Persisted/injected settings may carry values of an unexpected runtime type
// (e.g. a number stored as a JSON string, or an int where a double is
// expected). These coerce where sensible and fall back otherwise, so a single
// malformed field never throws and discards the whole settings blob.

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(dynamic v, double fallback) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool _asBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

String _asString(dynamic v, String fallback) => v is String ? v : fallback;
