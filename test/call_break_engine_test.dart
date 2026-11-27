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
    for (final player in game.players) { player.bid = 3; }
    final lead = game.players[game.turn].hand.first;
    game.play(game.turn, lead);
    final next = game.turn;
    final legal = game.legalCards(next);
    if (game.players[next].hand.any((c) => c.suit == lead.suit)) {
      expect(legal.every((c) => c.suit == lead.suit), isTrue);
    } else {
      final spades = game.players[next].hand.where((c) => c.suit == CardSuit.spades).toList();
      expect(legal, spades.isNotEmpty ? spades : game.players[next].hand);
    }
  });

  test('requires a spade cut when void in the led suit', () {
    final heart = PlayingCard(rank: CardRank.ace, suit: CardSuit.hearts);
    final spade = PlayingCard(rank: CardRank.two, suit: CardSuit.spades);
    final club = PlayingCard(rank: CardRank.three, suit: CardSuit.clubs);
    final legal = CallBreakEngine.legalCardsForHand(
      [spade, club], leadSuit: CardSuit.hearts,
      trick: [(player: 0, card: heart)],
    );
    expect(legal, [spade]);
    expect(CallBreakEngine.legalCardsForHand(
      [club], leadSuit: CardSuit.hearts,
      trick: [(player: 0, card: heart)],
    ), [club]);
  });

  test('does not force a trump when unable to overtrump an existing trump', () {
    final heart = PlayingCard(rank: CardRank.ace, suit: CardSuit.hearts);
    final tableTrump = PlayingCard(rank: CardRank.ten, suit: CardSuit.spades);
    final lowTrump = PlayingCard(rank: CardRank.five, suit: CardSuit.spades);
    final club = PlayingCard(rank: CardRank.three, suit: CardSuit.clubs);
    final hand = [lowTrump, club];
    final legal = CallBreakEngine.legalCardsForHand(
      hand,
      leadSuit: CardSuit.hearts,
      trick: [
        (player: 0, card: heart),
        (player: 1, card: tableTrump),
      ],
    );
    expect(legal, hand);
  });

  test('requires a higher trump when it can overtake an existing trump', () {
    final heart = PlayingCard(rank: CardRank.ace, suit: CardSuit.hearts);
    final tableTrump = PlayingCard(rank: CardRank.ten, suit: CardSuit.spades);
    final highTrump = PlayingCard(rank: CardRank.ace, suit: CardSuit.spades);
    final club = PlayingCard(rank: CardRank.three, suit: CardSuit.clubs);
    final legal = CallBreakEngine.legalCardsForHand(
      [highTrump, club],
      leadSuit: CardSuit.hearts,
      trick: [
        (player: 0, card: heart),
        (player: 1, card: tableTrump),
      ],
    );
    expect(legal, [highTrump]);
  });

  test('allows a lower led-suit card after a trump has cut the trick', () {
    final lowLead = PlayingCard(rank: CardRank.three, suit: CardSuit.diamonds);
    final highLead = PlayingCard(rank: CardRank.eight, suit: CardSuit.diamonds);
    final trump = PlayingCard(rank: CardRank.two, suit: CardSuit.spades);
    final king = PlayingCard(rank: CardRank.king, suit: CardSuit.diamonds);
    final seven = PlayingCard(rank: CardRank.seven, suit: CardSuit.diamonds);
    final hand = [king, seven];

    final legal = CallBreakEngine.legalCardsForHand(
      hand,
      leadSuit: CardSuit.diamonds,
      trick: [
        (player: 0, card: lowLead),
        (player: 1, card: highLead),
        (player: 2, card: trump),
      ],
    );

    expect(legal, hand);
  });

  test('supports 13 rounds and preserves each round scorecard', () {
    final game = makeGame()..roundsToPlay = 13;
    for (var round = 1; round <= 13; round++) {
      game.deal();
      for (final p in game.players) { p.bid = 2; }
      while (!game.complete) {
        game.play(game.turn, game.legalCards(game.turn).first);
      }
      expect(game.roundHistory, hasLength(round));
      if (round < 13) {
        expect(game.matchComplete, isFalse);
        game.nextRound();
      }
    }
    expect(game.matchComplete, isTrue);
    expect(game.roundHistory, hasLength(13));
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
