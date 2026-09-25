import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/signal_source.dart';
import 'recording_format.dart';
import 'recording_store.dart';

RecordingStore createRecordingStore() => IoRecordingStore();

/// Keeps the library in `<app documents>/recordings/`.
class IoRecordingStore implements RecordingStore {
  IoRecordingStore({
    Future<Directory> Function()? directory,
    this.maxRecordingBytes = kMaxRecordingBytes,
  }) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  /// Size at which a recording stops accepting frames.
  final int maxRecordingBytes;

  static Future<Directory> _defaultDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}recordings');
  }

  Future<Directory> _ensureDirectory() async {
    final dir = await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _join(Directory dir, String file) =>
      '${dir.path}${Platform.pathSeparator}$file';

  @override
  bool get isSupported => true;

  @override
  Future<RecordingSink> startRecording({
    required int sampleRate,
    required bool isComplex,
    double? centerFrequencyHz,
  }) async {
    final dir = await _ensureDirectory();
    final now = DateTime.now();
    final stem = recordingStem('spectral', now);

    if (isComplex) {
      final meta = File(_join(dir, '$stem$kSigmfMetaExtension'));
      await meta.writeAsString(buildSigmfMeta(
        sampleRate: sampleRate,
        centerFrequencyHz: centerFrequencyHz ?? 0,
        startedAt: now,
      ));
      final data = File(_join(dir, '$stem$kSigmfDataExtension'));
      return _FileRecordingSink(
        info: RecordingInfo(
          name: stem,
          format: RecordingFormat.sigmf,
          dataPath: data.path,
          metaPath: meta.path,
          sampleRate: sampleRate,
          isComplex: true,
          centerFrequencyHz: centerFrequencyHz,
          createdAt: now,
        ),
        sink: data.openWrite(),
        maxBytes: maxRecordingBytes,
      );
    }

    final wav = File(_join(dir, '$stem.wav'));
    final sink = wav.openWrite()..add(buildWavHeader(sampleRate: sampleRate));
    return _FileRecordingSink(
      info: RecordingInfo(
        name: stem,
        format: RecordingFormat.wav,
        dataPath: wav.path,
        sampleRate: sampleRate,
        dataOffset: kWavHeaderBytes,
        createdAt: now,
      ),
      sink: sink,
      maxBytes: maxRecordingBytes,
    );
  }

  @override
  Future<List<RecordingInfo>> list() async {
    final dir = await _directory();
    if (!await dir.exists()) return const [];
    final entries = <RecordingInfo>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final info = await _describe(entity);
        if (info != null) entries.add(info);
      } catch (e) {
        debugPrint('Skipping unreadable recording ${entity.path}: $e');
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<RecordingInfo?> _describe(File file) async {
    final path = file.path;
    final String base = path.split(Platform.pathSeparator).last;
    final stat = await file.stat();

    if (base.endsWith('.wav')) {
      final raf = await file.open();
      final Uint8List head;
      try {
        head = await raf.read(4096);
      } finally {
        await raf.close();
      }
      final layout = parseWavHeader(head, fileLength: stat.size);
      if (layout == null) return null;
      return RecordingInfo(
        name: base.substring(0, base.length - 4),
        format: RecordingFormat.wav,
        dataPath: path,
        sampleRate: layout.sampleRate,
        dataOffset: layout.dataOffset,
        dataBytes: layout.dataBytes,
        createdAt: stat.modified,
      );
    }

    if (base.endsWith(kSigmfMetaExtension)) {
      final stem = base.substring(0, base.length - kSigmfMetaExtension.length);
      final data = File(_join(file.parent, '$stem$kSigmfDataExtension'));
      if (!await data.exists()) return null;
      final meta = parseSigmfMeta(await file.readAsString());
      if (meta == null) return null;
      final int size = await data.length();
      return RecordingInfo(
        name: stem,
        format: RecordingFormat.sigmf,
        dataPath: data.path,
        metaPath: path,
        sampleRate: meta.sampleRate,
        isComplex: true,
        centerFrequencyHz: meta.centerFrequencyHz,
        dataBytes: size - size % bytesPerFrame(isComplex: true),
        createdAt: (await data.stat()).modified,
      );
    }

    if (base.endsWith('.csv')) {
      return RecordingInfo(
        name: base.substring(0, base.length - 4),
        format: RecordingFormat.csv,
        dataPath: path,
        dataBytes: stat.size,
        createdAt: stat.modified,
      );
    }
    return null;
  }

  @override
  SignalSource openPlayback(RecordingInfo info) => FileRecordingSource(info);

  @override
  Future<void> delete(RecordingInfo info) async {
    for (final p in info.paths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Future<void> share(RecordingInfo info, {Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final p in info.paths) XFile(p)],
      subject: info.name,
      sharePositionOrigin: origin,
    ));
  }

  @override
  Future<RecordingInfo> saveCsv(String csv) async {
    final dir = await _ensureDirectory();
    final now = DateTime.now();
    final stem = recordingStem('spectrum', now);
    final file = File(_join(dir, '$stem.csv'));
    await file.writeAsString(csv);
    return RecordingInfo(
      name: stem,
      format: RecordingFormat.csv,
      dataPath: file.path,
      dataBytes: await file.length(),
      createdAt: now,
    );
  }
}

class _FileRecordingSink implements RecordingSink {
  _FileRecordingSink({
    required RecordingInfo info,
    required IOSink sink,
    required int maxBytes,
  })  : _info = info,
        _sink = sink,
        _maxBytes = maxBytes;

  final RecordingInfo _info;
  final IOSink _sink;
  final int _maxBytes;
  int _bytes = 0;
  bool _full = false;
  bool _closed = false;

  int get _frameBytes => bytesPerFrame(isComplex: _info.isComplex);

  @override
  int get bytesWritten => _bytes;

  @override
  bool get isFull => _full;

  @override
  Duration get duration => Duration(
      microseconds: (_bytes ~/ _frameBytes * 1e6 / _info.sampleRate).round());

  @override
  void add(Float64List samples) {
    if (_closed || _full || samples.isEmpty) return;
    Uint8List bytes = encodeInt16(samples);
    final int room = _maxBytes - _bytes;
    if (bytes.length >= room) {
      bytes = Uint8List.sublistView(bytes, 0, room - room % _frameBytes);
      _full = true;
    }
    _sink.add(bytes);
    _bytes += bytes.length;
  }

  @override
  Future<RecordingInfo> close() async {
    if (!_closed) {
      _closed = true;
      await _sink.flush();
      await _sink.close();
      if (_info.format == RecordingFormat.wav) {
        // Append mode seeks to the end without O_APPEND, so positioned writes
        // land where asked; write mode would truncate the samples away.
        final raf = await File(_info.dataPath).open(mode: FileMode.append);
        try {
          await raf.setPosition(0);
          await raf.writeFrom(
              buildWavHeader(sampleRate: _info.sampleRate, dataBytes: _bytes));
        } finally {
          await raf.close();
        }
      }
    }
    return RecordingInfo(
      name: _info.name,
      format: _info.format,
      dataPath: _info.dataPath,
      metaPath: _info.metaPath,
      sampleRate: _info.sampleRate,
      isComplex: _info.isComplex,
      centerFrequencyHz: _info.centerFrequencyHz,
      dataOffset: _info.dataOffset,
      dataBytes: _bytes,
      createdAt: _info.createdAt,
    );
  }
}

/// Replays a recording at its original sample rate, looping at the end.
///
/// Pacing follows a stopwatch rather than counting ticks, so timer jitter
/// never drifts the playback rate; after a stall it skips ahead instead of
/// bursting the backlog into the pipeline.
class FileRecordingSource implements SignalSource {
  FileRecordingSource(this.info,
      {this.tick = const Duration(milliseconds: 25)});

  final RecordingInfo info;
  final Duration tick;

  final _controller = StreamController<Float64List>.broadcast();
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  RandomAccessFile? _file;
  int _position = 0; // Byte offset within the sample payload.
  int _emittedFrames = 0;
  bool _busy = false;
  bool _disposed = false;

  int get _frameBytes => bytesPerFrame(isComplex: info.isComplex);

  @override
  Stream<Float64List> get dataStream => _controller.stream;

  @override
  int get sampleRate => info.sampleRate;

  @override
  bool get isComplex => info.isComplex;

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<void> startCapture() async {
    if (_disposed || _timer != null) return;
    if (info.dataBytes < _frameBytes) return;
    _file ??= await File(info.dataPath).open();
    if (_disposed) return;
    _emittedFrames = 0;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(tick, (_) => _pump());
  }

  Future<void> _pump() async {
    final file = _file;
    if (_busy || file == null || _disposed) return;
    _busy = true;
    try {
      final int due =
          (_clock.elapsedMicroseconds * info.sampleRate / 1e6).floor();
      int frames = due - _emittedFrames;
      final int maxFrames = math.max(1, info.sampleRate ~/ 5);
      if (frames > maxFrames) {
        _emittedFrames = due - maxFrames;
        frames = maxFrames;
      }
      if (frames <= 0) return;

      final builder = BytesBuilder(copy: false);
      int remaining = frames * _frameBytes;
      while (remaining > 0) {
        final int toRead = math.min(remaining, info.dataBytes - _position);
        await file.setPosition(info.dataOffset + _position);
        final chunk = await file.read(toRead);
        if (chunk.isEmpty) break;
        builder.add(chunk);
        remaining -= chunk.length;
        _position += chunk.length;
        if (_position >= info.dataBytes) _position = 0;
      }
      _emittedFrames += frames;
      if (_disposed || _timer == null) return;
      final bytes = builder.takeBytes();
      _controller.add(decodeInt16(
          Uint8List.sublistView(bytes, 0, bytes.length - bytes.length % 2)));
    } catch (e) {
      debugPrint('Recording playback error: $e');
    } finally {
      _busy = false;
      if (_disposed) await _closeFile();
    }
  }

  Future<void> _closeFile() async {
    final file = _file;
    _file = null;
    await file?.close();
  }

  @override
  Future<void> stopCapture() async {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    stopCapture();
    // A read in flight owns the file; _pump closes it once the read returns.
    if (!_busy) unawaited(_closeFile());
    _controller.close();
  }
}
