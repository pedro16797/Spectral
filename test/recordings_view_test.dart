import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';
import 'package:spectral/src/core/settings_model.dart';
import 'package:spectral/src/core/signal_controller.dart';
import 'package:spectral/src/recording/recording_store.dart';
import 'package:spectral/src/ui/recordings_view.dart';
import 'package:spectral/src/utils/localization_helper.dart';

import 'signal_controller_test.dart' show FakeRecordingStore, FakeSignalSource;

class FileAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(File(key).readAsStringSync());

  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  setUpAll(() => LocalizationHelper.load('en', FileAssetBundle()));

  final wav = RecordingInfo(
    name: 'spectral_20260924_101500',
    format: RecordingFormat.wav,
    dataPath: 'a.wav',
    sampleRate: 44100,
    dataOffset: 44,
    dataBytes: 44100 * 2 * 5,
    createdAt: DateTime(2026, 9, 24),
  );
  final csv = RecordingInfo(
    name: 'spectrum_20260924_101000',
    format: RecordingFormat.csv,
    dataPath: 'b.csv',
    dataBytes: 2048,
    createdAt: DateTime(2026, 9, 23),
  );

  Future<(SignalController, FakeRecordingStore)> pumpView(
      WidgetTester tester) async {
    final store = FakeRecordingStore()..entries = [wav, csv];
    final controller = SignalController(
      settings: const AppSettings(),
      recordingStore: store,
      sourceFactory: (_, __) => FakeSignalSource(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: RecordingsView(controller: controller),
    ));
    await tester.pump();
    return (controller, store);
  }

  testWidgets('lists entries and offers playback only for recordings',
      (tester) async {
    await pumpView(tester);

    expect(find.text('spectral_20260924_101500'), findsOneWidget);
    expect(find.text('spectrum_20260924_101000'), findsOneWidget);
    expect(find.text('Audio · 44.1 kHz · 0:05 · 431 KB'), findsOneWidget);
    // One play button: the CSV has nothing to replay.
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Share'), findsNWidgets(2));
  });

  testWidgets('recording and export are unavailable while idle',
      (tester) async {
    await pumpView(tester);

    expect(find.text('Start a live capture to record it.'), findsOneWidget);
    expect(
        find.text('Nothing to export until the spectrum shows a signal.'),
        findsOneWidget);
    final record = tester.widget<InkWell>(find.byKey(const Key('recordings.record')));
    expect(record.onTap, isNull);
  });

  testWidgets('playing an entry hands it to the controller', (tester) async {
    final (controller, store) = await pumpView(tester);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(controller.playbackRecording, same(wav));
    expect(store.playbackSources.single.started, isTrue);
  });

  testWidgets('the header fits a narrow phone with every action showing',
      (tester) async {
    // The test font draws every glyph as a full square, so text runs far
    // wider than on a device: at this width the old fixed-width title pushed
    // the header actions ~30 px off screen.
    tester.view.physicalSize = const Size(410, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // RF shows the spectrum-view toggle too: four header actions in portrait.
    await tester.pumpWidget(const SpectralApp(
      initialSettings: AppSettings(
        signalSource: SignalSourceType.rf,
        rfSource: RfSourceType.mock,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Recordings'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
  });
}
