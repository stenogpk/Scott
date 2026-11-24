import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SCOTT home page shows the multiplayer modes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'scott_profile_name': 'Tester',
      'scott_profile_gender': 'अन्य',
    });
    await tester.pumpWidget(const ScottApp());
    await tester.pumpAndSettle();

    expect(find.text('SCOTT'), findsWidgets);
    expect(find.text('Online Multiplayer'), findsOneWidget);
    expect(find.text('Local Wi-Fi Multiplayer'), findsOneWidget);
    expect(find.textContaining('Pass & Play'), findsNothing);
  });
}
