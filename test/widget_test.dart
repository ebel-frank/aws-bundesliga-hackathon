import 'package:flutter_test/flutter_test.dart';

import 'package:live_prediction_arena/main.dart';

void main() {
  testWidgets('App smoke test - widget builds', (WidgetTester tester) async {
    await tester.pumpWidget(const LivePredictionArenaApp());
    await tester.pump();

    // Verify the app title is rendered somewhere in the widget tree
    expect(find.text('ARENA'), findsOneWidget);
  });
}
