import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// On-disk formats Spectral writes. Audio goes to a standard WAV so any audio
/// tool can open it; I/Q goes to SigMF (a data file plus a JSON sidecar),
/// which inspectrum, GNU Radio and SigMF-aware tools understand.
enum RecordingFormat {
  /// 16-bit PCM mono WAV.
  wav,

  /// SigMF recording with interleaved 16-bit little-endian I/Q (`ci16_le`).
  sigmf,

  /// A spectrum snapshot exported as CSV. Not playable.
  csv,
}

/// Recordings stop on their own at this size: WAV's 32-bit size fields cap
/// out at 4 GiB, and an unattended capture should not fill the device.
const int kMaxRecordingBytes = 1 << 30;

const String kSigmfDatatype = 'ci16_le';
const String kSigmfDataExtension = '.sigmf-data';
const String kSigmfMetaExtension = '.sigmf-meta';

/// Bytes per sample frame: one int16 for mono audio, two for an I/Q pair.
int bytesPerFrame({required bool isComplex}) => isComplex ? 4 : 2;

/// Describes a file in the recordings library.
class RecordingInfo {
  /// Shared file stem, e.g. `spectral_20260924_101500`.
  final String name;
  final RecordingFormat format;

  /// The file holding the samples (or the CSV itself).
  final String dataPath;

  /// SigMF metadata sidecar; null for other formats.
  final String? metaPath;

  final int sampleRate;
  final bool isComplex;

  /// Tuned centre of an I/Q capture, in Hz.
  final double? centerFrequencyHz;

  /// Byte offset of the first sample within [dataPath].
  final int dataOffset;

  /// Sample payload size in bytes.
  final int dataBytes;

  final DateTime createdAt;

  const RecordingInfo({
    required this.name,
    required this.format,
    required this.dataPath,
    this.metaPath,
    this.sampleRate = 0,
    this.isComplex = false,
    this.centerFrequencyHz,
    this.dataOffset = 0,
    this.dataBytes = 0,
    required this.createdAt,
  });

  bool get isPlayable => format != RecordingFormat.csv && sampleRate > 0;

  Duration get duration {
    if (sampleRate <= 0) return Duration.zero;
    final frames = dataBytes ~/ bytesPerFrame(isComplex: isComplex);
    return Duration(microseconds: (frames * 1e6 / sampleRate).round());
  }

  /// Every file that belongs to this entry, for sharing or deletion.
  List<String> get paths => [dataPath, if (metaPath != null) metaPath!];
}

/// `spectral_20260924_101500`-style stem, sortable and filesystem-safe.
String recordingStem(String prefix, DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${prefix}_${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

// ---- Sample encoding ----

/// Quantizes normalized samples ([-1, 1]) to little-endian int16, clamping
/// anything out of range rather than letting it wrap. Real samples map to
/// mono PCM; interleaved I/Q maps to `ci16_le` unchanged.
Uint8List encodeInt16(Float64List samples) {
  final out = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    final double s = samples[i];
    final double c = s > 1 ? 1 : (s < -1 ? -1 : (s.isNaN ? 0 : s));
    out.setInt16(i * 2, (c * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Inverse of [encodeInt16]. A trailing odd byte is ignored.
Float64List decodeInt16(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final out = Float64List(bytes.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32767.0;
  }
  return out;
}

// ---- WAV ----

const int kWavHeaderBytes = 44;

/// A canonical 44-byte PCM16 mono header. Written with [dataBytes] = 0 when
/// recording starts and patched on stop; [parseWavHeader] copes with a file
/// whose header was never patched (the app died mid-recording).
Uint8List buildWavHeader({required int sampleRate, int dataBytes = 0}) {
  final h = ByteData(kWavHeaderBytes);
  void tag(int offset, String s) {
    for (int i = 0; i < 4; i++) {
      h.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little); // fmt chunk size
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  h.setUint16(32, 2, Endian.little); // block align
  h.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return h.buffer.asUint8List();
}

/// Where the samples live in a PCM16 mono WAV.
class WavLayout {
  final int sampleRate;
  final int dataOffset;
  final int dataBytes;
  const WavLayout(this.sampleRate, this.dataOffset, this.dataBytes);
}

/// Walks the RIFF chunks of [head] (the first few KB of the file) and returns
/// the sample layout, or null for anything that is not PCM16 mono.
/// [fileLength] bounds the data chunk, so a truncated or unpatched file still
/// plays everything that actually reached the disk.
WavLayout? parseWavHeader(Uint8List head, {required int fileLength}) {
  if (head.length < 12) return null;
  final v = ByteData.sublistView(head);
  String tagAt(int o) => String.fromCharCodes(head.sublist(o, o + 4));
  if (tagAt(0) != 'RIFF' || tagAt(8) != 'WAVE') return null;

  int? sampleRate;
  int offset = 12;
  while (offset + 8 <= head.length) {
    final String id = tagAt(offset);
    final int size = v.getUint32(offset + 4, Endian.little);
    final int body = offset + 8;
    if (id == 'fmt ') {
      if (body + 16 > head.length) return null;
      final int audioFormat = v.getUint16(body, Endian.little);
      final int channels = v.getUint16(body + 2, Endian.little);
      final int bits = v.getUint16(body + 14, Endian.little);
      if (audioFormat != 1 || channels != 1 || bits != 16) return null;
      sampleRate = v.getUint32(body + 4, Endian.little);
    } else if (id == 'data') {
      if (sampleRate == null || sampleRate <= 0) return null;
      final int available = math.max(0, fileLength - body);
      final int bytes = (size == 0 || size > available) ? available : size;
      return WavLayout(sampleRate, body, bytes - bytes % 2);
    }
    // Chunks are word-aligned.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

// ---- SigMF ----

/// SigMF metadata for a `ci16_le` capture. Written at the start of the
/// recording — everything it holds is known up front — so an interrupted
/// capture still has a valid description.
String buildSigmfMeta({
  required int sampleRate,
  required double centerFrequencyHz,
  required DateTime startedAt,
  String recorder = 'Spectral',
}) {
  final meta = {
    'global': {
      'core:datatype': kSigmfDatatype,
      'core:sample_rate': sampleRate,
      'core:version': '1.0.0',
      'core:recorder': recorder,
    },
    'captures': [
      {
        'core:sample_start': 0,
        'core:frequency': centerFrequencyHz,
        'core:datetime': startedAt.toUtc().toIso8601String(),
      }
    ],
    'annotations': <Object>[],
  };
  return const JsonEncoder.withIndent('  ').convert(meta);
}

/// Sample rate and centre frequency from a SigMF sidecar, or null if it does
/// not describe a `ci16_le` capture this app can play.
({int sampleRate, double centerFrequencyHz})? parseSigmfMeta(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final global = decoded['global'];
    if (global is! Map || global['core:datatype'] != kSigmfDatatype) {
      return null;
    }
    final rate = global['core:sample_rate'];
    if (rate is! num || rate <= 0) return null;
    double centre = 0;
    final captures = decoded['captures'];
    if (captures is List && captures.isNotEmpty && captures.first is Map) {
      final f = (captures.first as Map)['core:frequency'];
      if (f is num) centre = f.toDouble();
    }
    return (sampleRate: rate.round(), centerFrequencyHz: centre);
  } catch (_) {
    return null;
  }
}

// ---- CSV ----

/// Frequency of each spectrum bin, matching how the FFT lays them out: a
/// complex spectrum is DC-centred and spans [bandStartHz, bandEndHz) in
/// `sampleRate / N` steps; a real one runs 0..Nyquist inclusive.
double binFrequencyHz(int index, int binCount,
    {required double bandStartHz,
    required double bandEndHz,
    required bool isComplex}) {
  final double span = bandEndHz - bandStartHz;
  if (isComplex) return bandStartHz + index * span / binCount;
  if (binCount < 2) return bandStartHz;
  return bandStartHz + index * span / (binCount - 1);
}

/// One spectrum frame as CSV: frequency, linear magnitude, magnitude in dB,
/// and the peak-hold trace when one is supplied with a matching length.
String buildSpectrumCsv({
  required List<double> magnitudes,
  List<double>? peakHold,
  required double bandStartHz,
  required double bandEndHz,
  required bool isComplex,
}) {
  final bool withPeak = peakHold != null && peakHold.length == magnitudes.length;
  String db(double m) =>
      m > 0 ? (20 * math.log(m) / math.ln10).toStringAsFixed(2) : '';
  final sb = StringBuffer(withPeak
      ? 'frequency_hz,magnitude,magnitude_db,peak_hold,peak_hold_db\n'
      : 'frequency_hz,magnitude,magnitude_db\n');
  for (int i = 0; i < magnitudes.length; i++) {
    final f = binFrequencyHz(i, magnitudes.length,
        bandStartHz: bandStartHz, bandEndHz: bandEndHz, isComplex: isComplex);
    final m = magnitudes[i];
    sb.write('${f.toStringAsFixed(1)},${m.toStringAsPrecision(6)},${db(m)}');
    if (withPeak) {
      final p = peakHold[i];
      sb.write(',${p.toStringAsPrecision(6)},${db(p)}');
    }
    sb.write('\n');
  }
  return sb.toString();
}
