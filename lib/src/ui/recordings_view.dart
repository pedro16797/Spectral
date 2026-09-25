import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/signal_controller.dart';
import '../recording/recording_store.dart';
import '../utils/frequency_formatter.dart';
import '../utils/localization_helper.dart';

/// The recordings library: record the live source, export the spectrum as
/// CSV, and replay, share or delete what has been saved.
class RecordingsView extends StatefulWidget {
  final SignalController controller;

  const RecordingsView({super.key, required this.controller});

  @override
  State<RecordingsView> createState() => _RecordingsViewState();
}

class _RecordingsViewState extends State<RecordingsView> {
  SignalController get _controller => widget.controller;

  List<RecordingInfo> _entries = const [];

  /// Refreshes the elapsed time and size while a recording runs; the
  /// controller only notifies on discrete changes.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _syncTicker();
    _reload();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncTicker();
    setState(() {});
  }

  void _syncTicker() {
    if (_controller.isRecording) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _reload() async {
    final entries = await _controller.recordingStore.list();
    if (mounted) setState(() => _entries = entries);
  }

  void _notify(String key) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(LocalizationHelper.get(key))));
  }

  Future<void> _toggleRecording() async {
    HapticFeedback.mediumImpact();
    if (_controller.isRecording) {
      final saved = await _controller.stopRecording();
      _notify(saved != null ? 'recordings.saved' : 'recordings.error');
      await _reload();
    } else if (!await _controller.startRecording()) {
      _notify('recordings.error');
    }
  }

  Future<void> _exportCsv(Rect? origin) async {
    HapticFeedback.lightImpact();
    final csv = _controller.spectrumCsv();
    if (csv == null) return;
    try {
      final saved = await _controller.recordingStore.saveCsv(csv);
      await _reload();
      _notify('recordings.exported');
      await _controller.recordingStore.share(saved, origin: origin);
    } catch (e) {
      debugPrint('CSV export failed: $e');
      _notify('recordings.error');
    }
  }

  Future<void> _play(RecordingInfo entry) async {
    HapticFeedback.lightImpact();
    await _controller.startPlayback(entry);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _share(RecordingInfo entry, Rect? origin) async {
    HapticFeedback.lightImpact();
    try {
      await _controller.recordingStore.share(entry, origin: origin);
    } catch (e) {
      debugPrint('Share failed: $e');
      _notify('recordings.error');
    }
  }

  Future<void> _delete(RecordingInfo entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(LocalizationHelper.get('recordings.delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocalizationHelper.get('recordings.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(LocalizationHelper.get('recordings.delete'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_controller.playbackRecording?.dataPath == entry.dataPath) {
      await _controller.stopPlayback();
    }
    await _controller.recordingStore.delete(entry);
    await _reload();
  }

  /// Screen rect of the widget behind [context]; anchors the iPad share
  /// popover to the button that opened it.
  static Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),
          Center(
            child: Container(
              width: size.width * (isLandscape ? 0.6 : 0.85),
              constraints: BoxConstraints(
                  maxHeight: size.height * (isLandscape ? 0.9 : 0.75)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: _buildContent(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final playback = _controller.playbackRecording;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Icon(Icons.folder_open_rounded,
                color: Colors.white70, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                LocalizationHelper.get('recordings.title').toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (playback != null) ...[
          _buildAction(
            key: const Key('recordings.stop_playback'),
            icon: Icons.stop_rounded,
            label: LocalizationHelper.get('recordings.stop_playback'),
            detail: playback.name,
            color: accent,
            onPressed: () async {
              HapticFeedback.lightImpact();
              await _controller.stopPlayback();
            },
          ),
          const SizedBox(height: 12),
        ],
        _buildRecordAction(),
        const SizedBox(height: 12),
        Builder(
          builder: (buttonContext) {
            final canExport = _controller.hasSpectrum;
            return _buildAction(
              key: const Key('recordings.export_csv'),
              icon: Icons.table_chart_outlined,
              label: LocalizationHelper.get('recordings.export_csv'),
              detail: canExport
                  ? null
                  : LocalizationHelper.get('recordings.export_unavailable'),
              onPressed:
                  canExport ? () => _exportCsv(_originOf(buttonContext)) : null,
            );
          },
        ),
        const SizedBox(height: 28),
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              LocalizationHelper.get('recordings.empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          )
        else
          for (final entry in _entries) _buildEntry(entry, accent),
      ],
    );
  }

  Widget _buildRecordAction() {
    final bool recording = _controller.isRecording;
    final bool enabled = recording || _controller.canRecord;
    final String? detail = recording
        ? '${_formatDuration(_controller.recordingDuration)} · '
            '${_formatBytes(_controller.recordingBytes)}'
        : (enabled ? null : LocalizationHelper.get('recordings.needs_capture'));
    return _buildAction(
      key: const Key('recordings.record'),
      icon: recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
      label: LocalizationHelper.get(
          recording ? 'recordings.stop' : 'recordings.start'),
      detail: detail,
      color: Colors.redAccent,
      onPressed: enabled ? _toggleRecording : null,
    );
  }

  Widget _buildAction({
    required Key key,
    required IconData icon,
    required String label,
    String? detail,
    Color? color,
    VoidCallback? onPressed,
  }) {
    final bool enabled = onPressed != null;
    final Color tint = enabled ? (color ?? Colors.white70) : Colors.white24;
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: enabled ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(RecordingInfo entry, Color accent) {
    final bool isPlaying =
        _controller.playbackRecording?.dataPath == entry.dataPath;
    final IconData icon = switch (entry.format) {
      RecordingFormat.wav => Icons.graphic_eq_rounded,
      RecordingFormat.sigmf => Icons.cell_tower_rounded,
      RecordingFormat.csv => Icons.table_chart_outlined,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: isPlaying ? accent : Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isPlaying ? accent : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(_describe(entry),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          if (entry.isPlayable)
            IconButton(
              tooltip: LocalizationHelper.get('recordings.play'),
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
              onPressed: isPlaying ? null : () => _play(entry),
            ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: LocalizationHelper.get('recordings.share'),
              icon: const Icon(Icons.ios_share_rounded,
                  color: Colors.white54, size: 20),
              onPressed: () => _share(entry, _originOf(buttonContext)),
            ),
          ),
          IconButton(
            tooltip: LocalizationHelper.get('recordings.delete'),
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.white38, size: 20),
            onPressed: () => _delete(entry),
          ),
        ],
      ),
    );
  }

  String _describe(RecordingInfo entry) {
    final parts = <String>[];
    switch (entry.format) {
      case RecordingFormat.wav:
        parts.add(LocalizationHelper.get('recordings.kind_audio'));
        parts.add(FrequencyFormatter.format(entry.sampleRate.toDouble()));
        parts.add(_formatDuration(entry.duration));
      case RecordingFormat.sigmf:
        parts.add(LocalizationHelper.get('recordings.kind_iq'));
        final centre = entry.centerFrequencyHz;
        if (centre != null && centre > 0) {
          parts.add(FrequencyFormatter.format(centre, precision: 3));
        }
        parts.add('${(entry.sampleRate / 1e6).toStringAsFixed(3)} MS/s');
        parts.add(_formatDuration(entry.duration));
      case RecordingFormat.csv:
        parts.add(LocalizationHelper.get('recordings.kind_csv'));
    }
    parts.add(_formatBytes(entry.dataBytes));
    return parts.join(' · ');
  }
}

String _formatDuration(Duration d) {
  final int minutes = d.inMinutes;
  final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}
