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

/// FFT window sizes the app supports; persisted values are snapped to this
/// set because `FFT(windowSize)` throws on anything else, which would kill
/// the spectrum on every frame.
const List<int> kFftWindowSizes = [512, 1024, 2048, 4096];

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
      theme: _asEnum(map['theme'], AppTheme.values, AppTheme.frost),
      signalSource: _asEnum(
          map['signalSource'], SignalSourceType.values, SignalSourceType.audio),
      rfSource: _asEnum(
          map['rfSource'], RfSourceType.values, RfSourceType.integrated),
      rtlTcpHost: _asString(map['rtlTcpHost'], '127.0.0.1'),
      rtlTcpPort: _asInt(map['rtlTcpPort'], 1234, min: 1, max: 65535),
      centerFrequency:
          _asDouble(map['centerFrequency'], 100.0, min: 0.001, max: 6000.0),
      rfBandwidth: _asDouble(map['rfBandwidth'], 2.0, min: 0.01, max: 100.0),
      fftWindowSize: _asWindowSize(map['fftWindowSize']),
      fftWindowType: _asEnum(
          map['fftWindowType'], FftWindowType.values, FftWindowType.hanning),
      language: _asString(map['language'], 'en'),
      // Bounds match the SQUISH dial / frequency-skew slider range.
      frequencySkew: _asDouble(map['frequencySkew'], 1.0, min: 0.1, max: 5.0),
      peakHoldEnabled: _asBool(map['peakHoldEnabled'], false),
      fftAveragingMode: _asEnum(map['fftAveragingMode'],
          FftAveragingMode.values, FftAveragingMode.none),
      fftAveragingCount: _asInt(map['fftAveragingCount'], 5, min: 1, max: 100),
      ppmCorrection:
          _asDouble(map['ppmCorrection'], 0.0, min: -1000.0, max: 1000.0),
      showHarmonics: _asBool(map['showHarmonics'], false),
      showSnr: _asBool(map['showSnr'], false),
      demodulationMode: _asEnum(map['demodulationMode'],
          DemodulationMode.values, DemodulationMode.none),
      audioOutputEnabled: _asBool(map['audioOutputEnabled'], false),
      spectrumView:
          _asEnum(map['spectrumView'], SpectrumView.values, SpectrumView.rf),
    );
  }
}

// ---- Lenient coercion helpers for AppSettings.fromMap ----
// Persisted/injected settings may carry values of an unexpected runtime type
// (e.g. a number stored as a JSON string, or an int where a double is
// expected) or out of the usable range. These coerce and clamp where sensible
// and fall back otherwise, so a single malformed field never throws, discards
// the whole settings blob, or (like a zero FFT window size) breaks the
// processing pipeline on every frame.

T _asEnum<T extends Enum>(dynamic v, List<T> values, T fallback) {
  for (final e in values) {
    if (e.name == v) return e;
  }
  return fallback;
}

int _asInt(dynamic v, int fallback, {int? min, int? max}) {
  int result = fallback;
  if (v is int) {
    result = v;
  } else if (v is num) {
    result = v.isFinite ? v.toInt() : fallback;
  } else if (v is String) {
    result = int.tryParse(v) ?? fallback;
  }
  if (min != null && result < min) return min;
  if (max != null && result > max) return max;
  return result;
}

double _asDouble(dynamic v, double fallback, {double? min, double? max}) {
  double result = fallback;
  if (v is num && v.isFinite) {
    result = v.toDouble();
  } else if (v is String) {
    final parsed = double.tryParse(v);
    if (parsed != null && parsed.isFinite) result = parsed;
  }
  if (min != null && result < min) return min;
  if (max != null && result > max) return max;
  return result;
}

bool _asBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

String _asString(dynamic v, String fallback) => v is String ? v : fallback;

int _asWindowSize(dynamic v) {
  final size = _asInt(v, 1024);
  return kFftWindowSizes.contains(size) ? size : 1024;
}
