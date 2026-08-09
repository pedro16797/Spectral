import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/src/rf/rtl_tcp_capture_service.dart';

void main() {
  group('buildRtlTcpCommand', () {
    test('encodes the opcode and a 32-bit big-endian argument', () {
      // 100 MHz = 0x05F5E100.
      final cmd = buildRtlTcpCommand(RtlTcpCommand.setFrequency, 100000000);
      expect(cmd, [0x01, 0x05, 0xF5, 0xE1, 0x00]);
    });

    test('encodes sample rate', () {
      // 2048000 = 0x001F4000.
      final cmd = buildRtlTcpCommand(RtlTcpCommand.setSampleRate, 2048000);
      expect(cmd, [0x02, 0x00, 0x1F, 0x40, 0x00]);
    });

    test('encodes negative frequency correction as 32-bit two\'s complement', () {
      final cmd = buildRtlTcpCommand(RtlTcpCommand.setFreqCorrection, -3);
      expect(cmd, [0x05, 0xFF, 0xFF, 0xFF, 0xFD]);
    });

    test('encodes small gain-mode argument', () {
      expect(buildRtlTcpCommand(RtlTcpCommand.setGainMode, 1), [0x03, 0x00, 0x00, 0x00, 0x01]);
    });
  });

  group('rtlIqBytesToDouble', () {
    test('maps unsigned 8-bit samples to [-1, 1) centered at 127.5', () {
      final data = Uint8List.fromList([0, 255, 128, 127]);
      final out = rtlIqBytesToDouble(data, 0, 4);
      expect(out[0], closeTo(-1.0, 1e-9)); // 0
      expect(out[1], closeTo(127.5 / 127.5, 1e-9)); // 255
      expect(out[2], closeTo(0.5 / 127.5, 1e-9)); // 128
      expect(out[3], closeTo(-0.5 / 127.5, 1e-9)); // 127
    });

    test('honors offset and length (skipping a header)', () {
      final data = Uint8List.fromList([9, 9, 0, 255]);
      final out = rtlIqBytesToDouble(data, 2, 2);
      expect(out.length, 2);
      expect(out[0], closeTo(-1.0, 1e-9));
      expect(out[1], closeTo(1.0, 1e-9));
    });
  });

  group('RtlIqChunker', () {
    double sample(int byte) => (byte - 127.5) / 127.5;

    test('passes whole pairs straight through', () {
      final chunker = RtlIqChunker();
      final out = chunker.process(Uint8List.fromList([10, 20, 30, 40]));
      expect(out, [sample(10), sample(20), sample(30), sample(40)]);
    });

    test('carries an odd trailing byte so I/Q pairs never swap', () {
      // TCP has no message boundaries: an odd split mid-pair must not shift
      // every subsequent Q into an I slot.
      final chunker = RtlIqChunker();
      final first = chunker.process(Uint8List.fromList([1, 2, 3]));
      expect(first, [sample(1), sample(2)]);

      final second = chunker.process(Uint8List.fromList([4, 5, 6]));
      expect(second, [sample(3), sample(4), sample(5), sample(6)]);
    });

    test('returns null until a whole pair is available', () {
      final chunker = RtlIqChunker();
      expect(chunker.process(Uint8List.fromList([7])), isNull);
      expect(chunker.process(Uint8List.fromList([8])), [sample(7), sample(8)]);
    });

    test('honors the offset used to skip the rtl_tcp header', () {
      final chunker = RtlIqChunker();
      final out = chunker.process(Uint8List.fromList([9, 9, 1, 2]), offset: 2);
      expect(out, [sample(1), sample(2)]);
    });

    test('reset drops a carried byte', () {
      final chunker = RtlIqChunker();
      chunker.process(Uint8List.fromList([1]));
      chunker.reset();
      expect(chunker.process(Uint8List.fromList([2, 3])),
          [sample(2), sample(3)]);
    });
  });
}
