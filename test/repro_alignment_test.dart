import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:spectral/src/utils/audio_utils.dart';

void main() {
  test('reproduce alignment issue in convertPcmToDouble', () {
    // Create a buffer and a view with an odd offset
    final buffer = Uint8List.fromList([0, 1, 2, 3, 4, 5]).buffer;
    final oddView = Uint8List.view(buffer, 1, 4);

    expect(oddView.offsetInBytes, 1);

    // This is expected to throw RangeError if not handled correctly
    expect(() => AudioUtils.convertPcmToDouble(oddView), returnsNormally);
  });
}
