import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/settings_model.dart';
import '../core/spectral_theme.dart';
import '../utils/spectrum_bins.dart';

/// Everything that decides which colour a stored FFT row becomes on screen.
/// When any of it changes, the baked texture no longer matches and is redrawn
/// from the history.
@immutable
class WaterfallView {
  /// Visible window, in Hz.
  final double minFreq;
  final double maxFreq;

  /// Full span the FFT data covers: centre ± sampleRate/2 for a complex RF
  /// spectrum, 0..Nyquist for audio.
  final double bandStart;
  final double bandEnd;

  final double frequencySkew;
  final AppTheme theme;

  const WaterfallView({
    required this.minFreq,
    required this.maxFreq,
    required this.bandStart,
    required this.bandEnd,
    this.frequencySkew = 1.0,
    this.theme = AppTheme.frost,
  });

  @override
  bool operator ==(Object other) =>
      other is WaterfallView &&
      other.minFreq == minFreq &&
      other.maxFreq == maxFreq &&
      other.bandStart == bandStart &&
      other.bandEnd == bandEnd &&
      other.frequencySkew == frequencySkew &&
      other.theme == theme;

  @override
  int get hashCode =>
      Object.hash(minFreq, maxFreq, bandStart, bandEnd, frequencySkew, theme);
}

/// The waterfall as a [columns] × [rows] texture, one texel per cell.
///
/// Painting every cell of every row each frame is what made the waterfall
/// expensive. Here a committed row costs one row of cells: the previous
/// texture is copied one row down on the GPU and only the new row is drawn on
/// top. The whole texture is redrawn from the history only when the view
/// changes (zoom, pan, skew, theme) or the history is cleared.
class WaterfallTexture {
  WaterfallTexture({required this.rows, this.columns = 160});

  final int rows;
  final int columns;

  ui.Image? _image;

  /// The newest row is at the top. Null until the first row arrives.
  ui.Image? get image => _image;

  WaterfallView? _view;
  SpectrumBinMapper? _mapper;
  int _epoch = -1;
  int _revision = 0;

  /// Brings the texture up to date with [history] (newest row first).
  /// [revision] counts committed rows and [epoch] counts clears; comparing
  /// them with the last call tells how many rows are new.
  void sync({
    required List<List<double>> history,
    required int revision,
    required int epoch,
    required WaterfallView view,
  }) {
    final bool viewChanged = view != _view;
    final int added = revision - _revision;
    if (!viewChanged && epoch == _epoch && added == 0) return;

    if (viewChanged) {
      _view = view;
      _mapper = SpectrumBinMapper(
        columnCount: columns,
        viewStartHz: view.minFreq,
        viewEndHz: view.maxFreq,
        bandStartHz: view.bandStart,
        bandEndHz: view.bandEnd,
        frequencySkew: view.frequencySkew,
      );
    }
    final bool incremental = !viewChanged &&
        epoch == _epoch &&
        _image != null &&
        added > 0 &&
        added < rows &&
        added <= history.length;
    _epoch = epoch;
    _revision = revision;

    if (history.isEmpty) {
      _replace(null);
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final int fresh;
    if (incremental) {
      // An integer offset at 1:1 scale copies the old texels exactly.
      canvas.drawImage(_image!, Offset(0, added.toDouble()), Paint());
      fresh = added;
    } else {
      fresh = history.length < rows ? history.length : rows;
    }
    _drawRows(canvas, history, fresh);
    final picture = recorder.endRecording();
    final next = picture.toImageSync(columns, rows);
    picture.dispose();
    _replace(next);
  }

  /// Draws the newest [count] rows of [history] at texture rows 0..count-1.
  ///
  /// Cells go out as one triangle mesh with per-vertex colours rather than a
  /// rect each: a full redraw is 25,600 cells, and a draw call per cell cost
  /// about twice as much to record and rasterize.
  void _drawRows(Canvas canvas, List<List<double>> history, int count) {
    final mapper = _mapper!;
    final theme = _view!.theme;
    final positions = Float32List(count * columns * 12);
    final colors = Int32List(count * columns * 6);
    int p = 0;
    int c = 0;
    for (int y = 0; y < count; y++) {
      final fft = history[y];
      if (fft.isEmpty) continue;
      final double y0 = y.toDouble(), y1 = y0 + 1;
      for (int x = 0; x < columns; x++) {
        // Peak across the covered bins, so a narrow carrier cannot fall
        // between columns and vanish.
        final normalized = normalizeMagnitude(mapper.peak(fft, x));
        if (normalized < 0.05) continue;
        final int argb =
            SpectralTheme.waterfallColor(theme, normalized).toARGB32();
        final double x0 = x.toDouble(), x1 = x0 + 1;
        // Two triangles per cell.
        positions
          ..[p++] = x0
          ..[p++] = y0
          ..[p++] = x1
          ..[p++] = y0
          ..[p++] = x0
          ..[p++] = y1
          ..[p++] = x1
          ..[p++] = y0
          ..[p++] = x1
          ..[p++] = y1
          ..[p++] = x0
          ..[p++] = y1;
        for (int k = 0; k < 6; k++) {
          colors[c++] = argb;
        }
      }
    }
    if (c == 0) return;
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(positions, 0, p),
        colors: Int32List.sublistView(colors, 0, c),
      ),
      // Vertex colours are the destination here: take them as they are.
      BlendMode.dst,
      Paint(),
    );
  }

  void _replace(ui.Image? next) {
    _image?.dispose();
    _image = next;
  }

  void dispose() => _replace(null);
}

/// Draws a [WaterfallTexture] stretched over the canvas, fading with age
/// towards the bottom.
class WaterfallPainter extends CustomPainter {
  final ui.Image? image;

  /// Row count of [image]; sets how tall one row is on screen.
  final int rows;

  /// How far the next row has filled, in (0, 1]. The texture slides down by
  /// that fraction of a row, with the newest row easing in from above, so
  /// slow speeds scroll instead of stepping a whole row per commit.
  final double scrollProgress;

  WaterfallPainter({
    required this.image,
    required this.rows,
    this.scrollProgress = 1.0,
  });

  /// Fade from 40% opacity at the top (newest) to nothing at the bottom.
  static const List<Color> _fade = [Color(0x66FFFFFF), Color(0x00FFFFFF)];

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null || size.isEmpty) return;

    final rect = Offset.zero & size;
    final double rowHeight = size.height / rows;
    final double dy = (scrollProgress - 1) * rowHeight;

    canvas.saveLayer(rect, Paint());
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, dy, size.width, size.height),
      // Nearest-neighbour: each cell is a crisp block, deliberately
      // pixelated. Bilinear smeared the 160×160 texture into a blurry,
      // low-res-looking background.
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _fade,
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WaterfallPainter oldDelegate) =>
      image != oldDelegate.image ||
      scrollProgress != oldDelegate.scrollProgress ||
      rows != oldDelegate.rows;
}
