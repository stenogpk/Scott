import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/main.dart';

void main() {
  testWidgets('SCOTT home page shows the multiplayer modes', (tester) async {
    await tester.pumpWidget(const ScottApp());

    expect(find.text('SCOTT'), findsOneWidget);
    expect(find.text('Online Multiplayer'), findsOneWidget);
    expect(find.text('Local Wi-Fi Multiplayer'), findsOneWidget);
    expect(find.textContaining('Pass & Play शामिल नहीं है'), findsOneWidget);
  });
}
