import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/game/scott_game_engine.dart';
import 'package:scott_game/game/playing_card.dart';

void main() {
  group('SCOTT card values', () {
    test('nine is zero and face cards have specified values', () {
      expect(CardRank.ace.value, 1);
      expect(CardRank.nine.value, 0);
      expect(CardRank.ten.value, 10);
      expect(CardRank.jack.value, 11);
      expect(CardRank.queen.value, 12);
      expect(CardRank.king.value, 13);
    });
  });

  group('SCOTT game setup', () {
    test('deals five cards to each of two to five players', () {
      final engine = ScottGameEngine();
      for (var count = 2; count <= 5; count++) {
        final state = engine.startGame(
          participants: [
            for (var i = 0; i < count; i++) (id: 'p$i', name: 'Player $i'),
          ],
          targetScore: 150,
        );
        expect(state.players.length, count);
        expect(state.players.every((p) => p.hand.length == 5), isTrue);
        expect(state.drawPile.length, 52 - count * 5);
      }
    });

    test('rejects fewer than two or more than five players', () {
      final engine = ScottGameEngine();
      expect(
        () => engine.startGame(participants: [(id: 'p1', name: 'One')], targetScore: 100),
        throwsArgumentError,
      );
      expect(
        () => engine.startGame(
          participants: [for (var i = 0; i < 6; i++) (id: 'p$i', name: 'P$i')],
          targetScore: 100,
        ),
        throwsArgumentError,
      );
    });
  });
}
