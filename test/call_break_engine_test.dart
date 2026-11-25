import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/game/call_break_engine.dart';

void main() {
  CallBreakEngine makeGame() => CallBreakEngine(seats: [
    (id: 'a', name: 'A', isBot: false),
    (id: 'b', name: 'B', isBot: true),
    (id: 'c', name: 'C', isBot: true),
    (id: 'd', name: 'D', isBot: true),
  ]);

  test('deals 52 unique cards as 13 per player', () {
    final game = makeGame()..deal();
    final all = game.players.expand((p) => p.hand).toList();
    expect(all.length, 52);
    expect(all.toSet().length, 52);
    expect(game.players.every((p) => p.hand.length == 13), isTrue);
  });

  test('requires following the led suit when possible', () {
    final game = makeGame()..deal();
    final lead = game.players[game.turn].hand.first;
    game.play(game.turn, lead);
    final next = game.turn;
    final legal = game.legalCards(next);
    if (game.players[next].hand.any((c) => c.suit == lead.suit)) {
      expect(legal.every((c) => c.suit == lead.suit), isTrue);
    } else {
      expect(legal.length, game.players[next].hand.length);
    }
  });

  test('rejects a combined bid below nine and resets bidding', () {
    final game = makeGame()..deal();
    for (var i = 0; i < 3; i++) {
      final player = game.turn;
      game.setBid(player, 1);
    }
    expect(() => game.setBid(game.turn, 1), throwsStateError);
    expect(game.players.every((p) => p.bid == 0), isTrue);
    expect(game.bidding, isTrue);
  });

  test('publishes private hands separately from public table state', () {
    final game = makeGame()..deal();
    final state = game.publicState();
    expect(state['players'], hasLength(4));
    expect((state['players'] as List).every((p) => !(p as Map).containsKey('hand')), isTrue);
    expect(game.privateHands().values.every((hand) => hand.length == 13), isTrue);
  });

  test('plays all 13 tricks and calculates bid scores', () {
    final game = makeGame()..deal();
    const bids = [3, 2, 2, 2];
    for (var i = 0; i < 4; i++) {
      game.players[i].bid = bids[i];
    }
    var guard = 0;
    while (!game.complete && guard < 52) {
      final player = game.turn;
      game.play(player, game.legalCards(player).first);
      guard++;
    }
    expect(game.complete, isTrue);
    expect(game.trickNumber, 13);
    for (final p in game.players) {
      final extra = p.tricks - p.bid;
      final expected = (extra < 0 || p.tricks > p.bid * 2)
          ? -p.bid.toDouble()
          : p.bid + extra / 10;
      expect(p.score, expected);
    }
  });
}
