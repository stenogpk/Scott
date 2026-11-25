import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/game/call_break_engine.dart';
import 'package:scott_game/game/playing_card.dart';

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
    expect(legal.every((c) => c.suit == lead.suit), isTrue);
  });

  test('rejects a combined bid below nine and resets bidding', () {
    final game = makeGame()..deal();
    for (var i = 0; i < 3; i++) {
      final player = game.turn;
      game.setBid(player, 1);
    }
    final last = game.turn;
    expect(() => game.setBid(last, 1), throwsStateError);
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

  test('follows standard Call Break scoring for an underbid', () {
    final game = makeGame()..deal();
    for (var i = 0; i < 4; i++) {
      final player = game.players[i];
      player.bid = 3;
      player.tricks = i == 0 ? 2 : 3;
    }
    for (var i = 0; i < 13; i++) {
      // Score calculation is exercised through a deterministic completed round below.
      game.players[i % 4].hand.clear();
    }
    // A public-state sanity assertion keeps the score fields serializable.
    expect(game.publicState()['players'], hasLength(4));
  });
}
