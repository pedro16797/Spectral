import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/recording/recording_format.dart';

void main() {
  group('int16 sample encoding', () {
    test('round-trips within one quantization step', () {
      final samples = Float64List.fromList([0, 0.5, -0.5, 1, -1, 0.123]);
      final decoded = decodeInt16(encodeInt16(samples));
      expect(decoded.length, samples.length);
      for (int i = 0; i < samples.length; i++) {
        expect(decoded[i], closeTo(samples[i], 1 / 32767));
      }
    });

    test('clamps out-of-range and NaN samples instead of wrapping', () {
      final decoded = decodeInt16(
          encodeInt16(Float64List.fromList([1.7, -3.0, double.nan])));
      expect(decoded[0], 1.0);
      expect(decoded[1], -1.0);
      expect(decoded[2], 0.0);
    });
  });

  group('WAV header', () {
    test('parses what it builds', () {
      final header = buildWavHeader(sampleRate: 44100, dataBytes: 8820);
      expect(header.length, kWavHeaderBytes);
      final layout = parseWavHeader(header, fileLength: 44 + 8820)!;
      expect(layout.sampleRate, 44100);
      expect(layout.dataOffset, 44);
      expect(layout.dataBytes, 8820);
    });

    test('an unpatched header plays everything that reached the disk', () {
      // The app died mid-recording: sizes are still the zero placeholders.
      final header = buildWavHeader(sampleRate: 48000);
      final layout = parseWavHeader(header, fileLength: 44 + 1001)!;
      expect(layout.dataBytes, 1000, reason: 'trimmed to whole samples');
    });

    test('a header claiming more data than the file holds is bounded', () {
      final header = buildWavHeader(sampleRate: 44100, dataBytes: 1 << 20);
      expect(parseWavHeader(header, fileLength: 44 + 200)!.dataBytes, 200);
    });

    test('skips unknown chunks before the data', () {
      final base = buildWavHeader(sampleRate: 8000, dataBytes: 4);
      final list = BytesBuilder()
        ..add(base.sublist(0, 36))
        ..add('LIST'.codeUnits)
        ..add([3, 0, 0, 0, 1, 2, 3, 0]) // Odd size plus its pad byte.
        ..add(base.sublist(36));
      final bytes = list.toBytes();
      final layout = parseWavHeader(bytes, fileLength: bytes.length + 4)!;
      expect(layout.sampleRate, 8000);
      expect(layout.dataOffset, 36 + 12 + 8);
    });

    test('rejects formats the player cannot decode', () {
      final stereo = buildWavHeader(sampleRate: 44100, dataBytes: 4);
      ByteData.sublistView(stereo).setUint16(22, 2, Endian.little);
      expect(parseWavHeader(stereo, fileLength: 48), isNull);

      final float = buildWavHeader(sampleRate: 44100, dataBytes: 4);
      ByteData.sublistView(float).setUint16(20, 3, Endian.little);
      expect(parseWavHeader(float, fileLength: 48), isNull);

      expect(parseWavHeader(Uint8List(44), fileLength: 44), isNull);
    });
  });

  group('SigMF metadata', () {
    test('parses what it builds', () {
      final json = buildSigmfMeta(
        sampleRate: 2048000,
        centerFrequencyHz: 100.1e6,
        startedAt: DateTime.utc(2026, 9, 24, 10, 15),
      );
      final meta = parseSigmfMeta(json)!;
      expect(meta.sampleRate, 2048000);
      expect(meta.centerFrequencyHz, 100.1e6);
      expect(json, contains('"core:datatype": "ci16_le"'));
      expect(json, contains('"core:version": "1.0.0"'));
      expect(json, contains('2026-09-24T10:15:00.000Z'));
    });

    test('rejects other datatypes and malformed documents', () {
      expect(
          parseSigmfMeta(
              '{"global":{"core:datatype":"cf32_le","core:sample_rate":1e6}}'),
          isNull);
      expect(parseSigmfMeta('{"global":{"core:datatype":"ci16_le"}}'), isNull);
      expect(parseSigmfMeta('not json'), isNull);
    });
  });

  group('spectrum bin frequencies', () {
    test('a complex spectrum is DC-centred in sampleRate/N steps', () {
      // 4-point complex FFT over 99..101 MHz: bins at -2, -1, 0, +1 * 0.5 MHz.
      final f = [
        for (int i = 0; i < 4; i++)
          binFrequencyHz(i, 4,
              bandStartHz: 99e6, bandEndHz: 101e6, isComplex: true)
      ];
      expect(f, [99e6, 99.5e6, 100e6, 100.5e6]);
    });

    test('a real spectrum runs 0..Nyquist inclusive', () {
      // A 1024-point real FFT keeps 513 bins; the last one is Nyquist.
      expect(
          binFrequencyHz(512, 513,
              bandStartHz: 0, bandEndHz: 22050, isComplex: false),
          22050);
      expect(
          binFrequencyHz(1, 513,
              bandStartHz: 0, bandEndHz: 22050, isComplex: false),
          closeTo(44100 / 1024, 1e-9));
    });
  });

  group('spectrum CSV', () {
    test('writes frequency, magnitude and dB per bin', () {
      final csv = buildSpectrumCsv(
        magnitudes: [1.0, 10.0, 0.0],
        bandStartHz: 0,
        bandEndHz: 100,
        isComplex: false,
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, 'frequency_hz,magnitude,magnitude_db');
      expect(lines[1], '0.0,1.00000,0.00');
      expect(lines[2], '50.0,10.0000,20.00');
      expect(lines[3], '100.0,0.00000,', reason: 'no dB for silence');
    });

    test('adds the peak-hold trace only when it matches the spectrum', () {
      final withPeak = buildSpectrumCsv(
        magnitudes: [1.0, 2.0],
        peakHold: [3.0, 4.0],
        bandStartHz: 0,
        bandEndHz: 10,
        isComplex: true,
      );
      expect(withPeak.split('\n').first, endsWith(',peak_hold,peak_hold_db'));

      final mismatched = buildSpectrumCsv(
        magnitudes: [1.0, 2.0],
        peakHold: [3.0],
        bandStartHz: 0,
        bandEndHz: 10,
        isComplex: true,
      );
      expect(mismatched.split('\n').first, isNot(contains('peak_hold')));
    });
  });

  test('recording duration follows the payload size and frame width', () {
    final audio = RecordingInfo(
      name: 'a',
      format: RecordingFormat.wav,
      dataPath: 'a.wav',
      sampleRate: 44100,
      dataBytes: 44100 * 2 * 3,
      createdAt: DateTime(2026),
    );
    expect(audio.duration, const Duration(seconds: 3));

    final iq = RecordingInfo(
      name: 'b',
      format: RecordingFormat.sigmf,
      dataPath: 'b.sigmf-data',
      metaPath: 'b.sigmf-meta',
      sampleRate: 1000000,
      isComplex: true,
      dataBytes: 1000000 * 4,
      createdAt: DateTime(2026),
    );
    expect(iq.duration, const Duration(seconds: 1));
    expect(iq.paths, ['b.sigmf-data', 'b.sigmf-meta']);
  });

  test('stems sort chronologically', () {
    expect(recordingStem('spectral', DateTime(2026, 9, 4, 7, 5, 3)),
        'spectral_20260904_070503');
  });
}
