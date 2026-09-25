import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/ui/waterfall_painter.dart';
import 'package:spectral/src/utils/spectrum_bins.dart';

void main() {
  // 513 bins (a 1024-point real FFT) over 0..22050 Hz, 160 columns: bin b
  // lands in column ~b * 160 / 513.
  const view = WaterfallView(
      minFreq: 0, maxFreq: 22050, bandStart: 0, bandEnd: 22050);

  /// A row that is silent except for one loud bin.
  Float64List tone(int bin, {double level = 90}) =>
      Float64List(513)..[bin] = level;

  /// Columns the shared bin mapper lights for [row] in [v]. A bin on a column
  /// boundary lights both neighbours, exactly as on screen.
  List<int> expectedColumns(List<double> row, [WaterfallView v = view]) {
    final mapper = SpectrumBinMapper(
      columnCount: 160,
      viewStartHz: v.minFreq,
      viewEndHz: v.maxFreq,
      bandStartHz: v.bandStart,
      bandEndHz: v.bandEnd,
      frequencySkew: v.frequencySkew,
    );
    return [
      for (int x = 0; x < 160; x++)
        if (normalizeMagnitude(mapper.peak(row, x)) >= 0.05) x
    ];
  }

  Future<Uint8List> pixels(ui.Image image) async =>
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();

  int alphaAt(Uint8List px, int width, int x, int y) =>
      px[(y * width + x) * 4 + 3];

  /// Columns in row [y] that hold a cell.
  List<int> litColumns(Uint8List px, int width, int y) =>
      [for (int x = 0; x < width; x++) if (alphaAt(px, width, x, y) > 0) x];

  test('the newest row is drawn at the top, one texel per cell', () async {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    final history = <List<double>>[tone(256)];
    texture.sync(history: history, revision: 1, epoch: 0, view: view);

    final image = texture.image!;
    expect(image.width, 160);
    expect(image.height, 8);
    final px = await pixels(image);
    expect(litColumns(px, 160, 0), expectedColumns(tone(256)));
    expect(litColumns(px, 160, 0), isNotEmpty);
    for (int y = 1; y < 8; y++) {
      expect(litColumns(px, 160, y), isEmpty, reason: 'row $y is unfilled');
    }
  });

  test('each commit shifts the texture down one row', () async {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    final history = <List<double>>[];
    int revision = 0;
    void commit(List<double> row) {
      history.insert(0, row);
      texture.sync(
          history: history, revision: ++revision, epoch: 0, view: view);
    }

    commit(tone(32));
    final first = texture.image;
    commit(tone(256));
    expect(texture.image, isNot(same(first)), reason: 'a new texture');

    final px = await pixels(texture.image!);
    expect(litColumns(px, 160, 0), expectedColumns(tone(256)),
        reason: 'newest on top');
    expect(litColumns(px, 160, 1), expectedColumns(tone(32)),
        reason: 'previous row moved down');
  });

  test('rows beyond the texture height fall off the bottom', () async {
    final texture = WaterfallTexture(rows: 4);
    addTearDown(texture.dispose);
    final history = <List<double>>[];
    for (int i = 0; i < 6; i++) {
      history.insert(0, tone(40 + i * 60));
      if (history.length > 4) history.removeLast();
      texture.sync(history: history, revision: i + 1, epoch: 0, view: view);
    }
    final px = await pixels(texture.image!);
    // Rows 5, 4, 3, 2 remain, newest first; rows 0 and 1 are gone.
    expect([for (int y = 0; y < 4; y++) litColumns(px, 160, y)],
        [for (final b in [340, 280, 220, 160]) expectedColumns(tone(b))]);
  });

  test('an incrementally built texture matches a full rebuild', () async {
    final incremental = WaterfallTexture(rows: 16);
    final rebuilt = WaterfallTexture(rows: 16);
    addTearDown(incremental.dispose);
    addTearDown(rebuilt.dispose);

    final history = <List<double>>[];
    int revision = 0;
    for (int i = 0; i < 40; i++) {
      final row = Float64List(513);
      for (int b = 0; b < 513; b++) {
        row[b] = ((b * 7 + i * 13) % 97).toDouble(); // Busy, varied rows.
      }
      history.insert(0, row);
      if (history.length > 16) history.removeLast();
      revision++;
      // Sometimes several rows land between two frames.
      if (i % 3 != 1) {
        incremental.sync(
            history: history, revision: revision, epoch: 0, view: view);
      }
    }
    incremental.sync(
        history: history, revision: revision, epoch: 0, view: view);
    rebuilt.sync(history: history, revision: revision, epoch: 0, view: view);

    expect(await pixels(incremental.image!), await pixels(rebuilt.image!));
  });

  test('a view change redraws every row from the history', () async {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    // A mid-level tone: a saturated one is the same colour in every theme.
    final history = <List<double>>[tone(256, level: 10), tone(256, level: 10)];
    texture.sync(history: history, revision: 2, epoch: 0, view: view);

    // Zoom into the lower half: the same bin now sits twice as far right.
    const zoomed = WaterfallView(
        minFreq: 0, maxFreq: 11025, bandStart: 0, bandEnd: 22050);
    texture.sync(history: history, revision: 2, epoch: 0, view: zoomed);
    final px = await pixels(texture.image!);
    final moved = expectedColumns(history.first, zoomed);
    expect(moved.first, greaterThan(150));
    expect(litColumns(px, 160, 0), moved);
    expect(litColumns(px, 160, 1), moved);

    // Theme changes recolour the history too.
    final before = await pixels(texture.image!);
    texture.sync(
        history: history,
        revision: 2,
        epoch: 0,
        view: const WaterfallView(
            minFreq: 0,
            maxFreq: 11025,
            bandStart: 0,
            bandEnd: 22050,
            theme: AppTheme.magma));
    expect(await pixels(texture.image!), isNot(before));
  });

  test('a clear drops the texture until rows arrive again', () async {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    texture.sync(history: [tone(100)], revision: 1, epoch: 0, view: view);
    expect(texture.image, isNotNull);
    texture.sync(history: const [], revision: 1, epoch: 1, view: view);
    expect(texture.image, isNull);
  });

  test('nothing is redrawn when nothing changed', () {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    final history = [tone(100)];
    texture.sync(history: history, revision: 1, epoch: 0, view: view);
    final image = texture.image;
    texture.sync(history: history, revision: 1, epoch: 0, view: view);
    expect(texture.image, same(image));
  });

  test('the painter repaints only when the image or scroll moves', () {
    final texture = WaterfallTexture(rows: 8);
    addTearDown(texture.dispose);
    texture.sync(history: [tone(100)], revision: 1, epoch: 0, view: view);
    final a = WaterfallPainter(image: texture.image, rows: 8);
    expect(a.shouldRepaint(WaterfallPainter(image: texture.image, rows: 8)),
        isFalse);
    expect(
        a.shouldRepaint(WaterfallPainter(
            image: texture.image, rows: 8, scrollProgress: 0.5)),
        isTrue);
  });
}
