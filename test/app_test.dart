import 'package:flutter_test/flutter_test.dart';
import 'package:spectral/main.dart';

void main() {
  testWidgets('Spectral app loads and shows title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SpectralApp());

    // Verify that our app shows the title 'Spectral'.
    expect(find.text('Spectral'), findsOneWidget);
    expect(find.text('Start Capture'), findsOneWidget);
  });
}
