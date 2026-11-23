import 'package:flutter_test/flutter_test.dart';
import 'package:scott_game/game/game_models.dart';
import 'package:scott_game/game/scott_game_engine.dart';
import 'package:scott_game/game/playing_card.dart';

PlayingCard card(CardRank rank, CardSuit suit) => PlayingCard(rank: rank, suit: suit);

GameState stateFor({
  required List<PlayingCard> firstHand,
  required List<PlayingCard> secondHand,
  int firstScore = 0,
  int target = 150,
}) =>
    GameState(
      players: [
        PlayerState(id: 'p1', name: 'One', hand: firstHand, score: firstScore),
        PlayerState(id: 'p2', name: 'Two', hand: secondHand),
      ],
      drawPile: [card(CardRank.four, CardSuit.clubs)],
      discardPile: const [],
      currentPlayerIndex: 0,
      targetScore: target,
      phase: GamePhase.waitingForTurn,
    );

void main() {
  group('SCOTT SHOW scoring', () {
    test('successful SHOW gives caller zero and opponents their own totals', () {
      final state = stateFor(
        firstHand: [card(CardRank.ace, CardSuit.hearts)],
        secondHand: [card(CardRank.five, CardSuit.spades)],
      );
      final result = ScottGameEngine().show(state, 'p1');
      expect(result.roundResult!.wasSuccessful, isTrue);
      expect(result.roundResult!.pointsAdded, {'p1': 0, 'p2': 5});
      expect(result.state.players[1].score, 5);
    });

    test('equal hand totals make SHOW fail and total goes to caller', () {
      final state = stateFor(
        firstHand: [card(CardRank.five, CardSuit.hearts)],
        secondHand: [card(CardRank.five, CardSuit.spades)],
      );
      final result = ScottGameEngine().show(state, 'p1');
      expect(result.roundResult!.wasSuccessful, isFalse);
      expect(result.roundResult!.pointsAdded, {'p1': 10, 'p2': 0});
      expect(result.state.players[0].score, 10);
    });

    test('caller is eliminated when failed SHOW reaches target score', () {
      final state = stateFor(
        firstHand: [card(CardRank.five, CardSuit.hearts)],
        secondHand: [card(CardRank.five, CardSuit.spades)],
        firstScore: 90,
        target: 100,
      );
      final result = ScottGameEngine().show(state, 'p1');
      expect(result.state.players[0].isEliminated, isTrue);
      expect(result.state.players[0].score, 100);
      expect(result.state.players[1].isEliminated, isFalse);
      expect(result.roundResult!.winnerId, 'p2');
      expect(result.state.phase, GamePhase.gameComplete);
    });
  });

  group('SCOTT turn skip', () {
    test('skipTurn advances to the next active player and skips eliminated players', () {
      final state = GameState(
        players: [
          PlayerState(id: 'p1', name: 'One', hand: [card(CardRank.two, CardSuit.clubs)]),
          PlayerState(id: 'p2', name: 'Two', hand: [card(CardRank.three, CardSuit.clubs)], isEliminated: true),
          PlayerState(id: 'p3', name: 'Three', hand: [card(CardRank.four, CardSuit.clubs)]),
        ],
        drawPile: const [],
        discardPile: const [],
        currentPlayerIndex: 0,
        targetScore: 150,
        phase: GamePhase.waitingForTurn,
      );
      final next = ScottGameEngine().skipTurn(state, 'p1');
      expect(next.currentPlayer.id, 'p3');
      expect(next.players[0].hand, state.players[0].hand);
      expect(next.phase, GamePhase.waitingForTurn);
    });
  });

  group('SCOTT discard validation', () {
    test('a nine can never be discarded', () {
      final state = stateFor(
        firstHand: [card(CardRank.nine, CardSuit.hearts), card(CardRank.two, CardSuit.clubs)],
        secondHand: [card(CardRank.ace, CardSuit.spades)],
      );
      expect(
        () => ScottGameEngine().discardAndDraw(
          state: state,
          playerId: 'p1',
          cardsToDiscard: [card(CardRank.nine, CardSuit.hearts)],
          drawSource: DrawSource.drawPile,
        ),
        throwsStateError,
      );
    });

    test('discarding a same-rank pair still draws exactly one card', () {
      final pair = [
        card(CardRank.king, CardSuit.hearts),
        card(CardRank.king, CardSuit.spades),
      ];
      final state = stateFor(
        firstHand: [...pair, card(CardRank.two, CardSuit.clubs), card(CardRank.three, CardSuit.clubs)],
        secondHand: [card(CardRank.ace, CardSuit.spades)],
      );
      final result = ScottGameEngine().discardAndDraw(
        state: state,
        playerId: 'p1',
        cardsToDiscard: pair,
        drawSource: DrawSource.drawPile,
      );
      expect(result.state.players[0].hand.length, 3);
      expect(result.state.drawPile, isEmpty);
      expect(result.state.discardPile, pair);
    });
  });
}
