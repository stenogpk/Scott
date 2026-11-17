import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/game/game_models.dart';
import 'package:scott_game/game/scott_game_engine.dart';
import 'package:scott_game/game/playing_card.dart';

PlayingCard c(CardRank rank, CardSuit suit) => PlayingCard(rank: rank, suit: suit);

void main() {
  group('SCOTT values and deck', () {
    test('all rank values follow the SCOTT table', () {
      expect(CardRank.ace.value, 1);
      expect(CardRank.two.value, 2);
      expect(CardRank.eight.value, 8);
      expect(CardRank.nine.value, 0);
      expect(CardRank.ten.value, 10);
      expect(CardRank.jack.value, 11);
      expect(CardRank.queen.value, 12);
      expect(CardRank.king.value, 13);
    });

    test('two to five players each receive five cards from a 52-card deck', () {
      final engine = ScottGameEngine();
      for (var n = 2; n <= 5; n++) {
        final state = engine.startGame(
          participants: [for (var i = 0; i < n; i++) (id: 'p$i', name: 'P$i')],
          targetScore: 150,
        );
        expect(state.players.every((p) => p.hand.length == 5), isTrue);
        expect(state.drawPile.length + state.players.fold<int>(0, (sum, p) => sum + p.hand.length), 52);
      }
    });
  });

  group('SHOW scoring and elimination', () {
    test('successful SHOW adds each opponent own hand total only', () {
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', hand: [c(CardRank.ace, CardSuit.hearts)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.five, CardSuit.clubs)]),
          PlayerState(id: 'c', name: 'C', hand: [c(CardRank.ten, CardSuit.spades)]),
        ],
        drawPile: const [], discardPile: const [], currentPlayerIndex: 0,
        targetScore: 150, phase: GamePhase.waitingForTurn,
      );
      final result = ScottGameEngine().show(state, 'a');
      expect(result.roundResult!.wasSuccessful, isTrue);
      expect(result.roundResult!.pointsAdded, {'a': 0, 'b': 5, 'c': 10});
      expect(result.state.players.map((p) => p.score).toList(), [0, 5, 10]);
      expect(result.state.phase, GamePhase.roundComplete);
    });

    test('equal hand total makes SHOW fail and sum goes to caller', () {
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', hand: [c(CardRank.five, CardSuit.hearts)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.five, CardSuit.spades)]),
        ],
        drawPile: const [], discardPile: const [], currentPlayerIndex: 0,
        targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      final result = ScottGameEngine().show(state, 'a');
      expect(result.roundResult!.wasSuccessful, isFalse);
      expect(result.roundResult!.pointsAdded, {'a': 10, 'b': 0});
    });

    test('reaching target eliminates player and leaves last player winner', () {
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', score: 90, hand: [c(CardRank.five, CardSuit.hearts)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.five, CardSuit.spades)]),
        ],
        drawPile: const [], discardPile: const [], currentPlayerIndex: 0,
        targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      final result = ScottGameEngine().show(state, 'a');
      expect(result.state.players.first.isEliminated, isTrue);
      expect(result.state.players.first.score, 100);
      expect(result.roundResult!.winnerId, 'b');
      expect(result.state.phase, GamePhase.gameComplete);
    });
  });

  group('Discard and draw rules', () {
    test('nine cannot be discarded', () {
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', hand: [c(CardRank.nine, CardSuit.hearts), c(CardRank.two, CardSuit.clubs)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.ace, CardSuit.spades)]),
        ],
        drawPile: [c(CardRank.four, CardSuit.clubs)], discardPile: const [],
        currentPlayerIndex: 0, targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      expect(() => ScottGameEngine().discardAndDraw(
        state: state, playerId: 'a', cardsToDiscard: [c(CardRank.nine, CardSuit.hearts)],
        drawSource: DrawSource.drawPile,
      ), throwsStateError);
    });

    test('same-rank pair discards together and draws exactly one', () {
      final pair = [c(CardRank.king, CardSuit.hearts), c(CardRank.king, CardSuit.spades)];
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', hand: [...pair, c(CardRank.two, CardSuit.clubs), c(CardRank.three, CardSuit.clubs)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.ace, CardSuit.spades)]),
        ],
        drawPile: [c(CardRank.four, CardSuit.clubs)], discardPile: const [],
        currentPlayerIndex: 0, targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      final turn = ScottGameEngine().discardAndDraw(state: state, playerId: 'a', cardsToDiscard: pair, drawSource: DrawSource.drawPile);
      expect(turn.state.players.first.hand.length, 3);
      expect(turn.state.drawPile, isEmpty);
      expect(turn.state.discardPile, pair);
      expect(turn.state.currentPlayer.id, 'b');
    });

    test('empty draw pile reshuffles face-up discards and draws one', () {
      final discarded = c(CardRank.four, CardSuit.clubs);
      final state = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', hand: [c(CardRank.two, CardSuit.hearts)]),
          PlayerState(id: 'b', name: 'B', hand: [c(CardRank.ace, CardSuit.spades)]),
        ],
        drawPile: const [], discardPile: const [], currentPlayerIndex: 0,
        targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      final withDiscard = GameState(
        players: state.players, drawPile: const [], discardPile: [discarded],
        currentPlayerIndex: 0, targetScore: 100, phase: GamePhase.waitingForTurn,
      );
      final turn = ScottGameEngine().discardAndDraw(
        state: withDiscard, playerId: 'a',
        cardsToDiscard: [c(CardRank.two, CardSuit.hearts)],
        drawSource: DrawSource.drawPile,
      );
      expect(turn.state.drawPile.length, 1);
      expect(turn.state.discardPile, isEmpty);
      expect(turn.state.players.first.hand.length, 1);
    });

    test('next round preserves cumulative scores and deals five to active players', () {
      final previous = GameState(
        players: [
          PlayerState(id: 'a', name: 'A', score: 20, hand: [c(CardRank.ace, CardSuit.hearts)], isEliminated: false),
          PlayerState(id: 'b', name: 'B', score: 150, hand: const [], isEliminated: true),
          PlayerState(id: 'c', name: 'C', score: 35, hand: [c(CardRank.five, CardSuit.clubs)], isEliminated: false),
        ],
        drawPile: const [], discardPile: const [], currentPlayerIndex: 0,
        targetScore: 150, phase: GamePhase.roundComplete,
      );
      final next = ScottGameEngine().startNextRound(previous, starterId: 'c');
      expect(next.players[0].score, 20);
      expect(next.players[1].score, 150);
      expect(next.players[1].hand, isEmpty);
      expect(next.players[0].hand.length, 5);
      expect(next.players[2].hand.length, 5);
      expect(next.players[2].isEliminated, isFalse);
      expect(next.currentPlayer.id, 'c');
      expect(next.roundNumber, 2);
    });
  });
}
