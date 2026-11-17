import 'dart:math';

import 'game_models.dart';
import 'playing_card.dart';

class ScottGameEngine {
  ScottGameEngine({Random? random}) : _random = random ?? Random();
  final Random _random;

  GameState startGame({
    required List<({String id, String name})> participants,
    required int targetScore,
  }) {
    if (participants.length < 2 || participants.length > 5) {
      throw ArgumentError('SCOTT requires 2 to 5 players.');
    }
    if (participants.map((p) => p.id).toSet().length != participants.length) {
      throw ArgumentError('Player IDs must be unique.');
    }
    if (participants.any((p) => p.name.trim().isEmpty)) {
      throw ArgumentError('Every player must have a name.');
    }
    if (targetScore <= 0) throw ArgumentError.value(targetScore, 'targetScore');

    final deck = _newDeck()..shuffle(_random);
    final players = participants.map((p) => PlayerState(id: p.id, name: p.name.trim())).toList();
    for (var cardIndex = 0; cardIndex < 5; cardIndex++) {
      for (var playerIndex = 0; playerIndex < players.length; playerIndex++) {
        final player = players[playerIndex];
        players[playerIndex] = player.copyWith(hand: [...player.hand, deck.removeLast()]);
      }
    }
    return GameState(
      players: players,
      drawPile: deck,
      discardPile: const [],
      currentPlayerIndex: 0,
      targetScore: targetScore,
      phase: GamePhase.waitingForTurn,
    );
  }

  GameState startNextRound(GameState previousState, {String? starterId}) {
    if (previousState.phase != GamePhase.roundComplete) {
      throw StateError('The previous round has not completed.');
    }
    final active = previousState.players.where((player) => !player.isEliminated).toList();
    if (active.length <= 1) {
      final winner = active.isEmpty ? null : active.single.id;
      return previousState.copyWith(phase: GamePhase.gameComplete, winnerId: winner);
    }
    final deck = _newDeck()..shuffle(_random);
    final dealt = <PlayerState>[];
    for (final player in previousState.players) {
      if (player.isEliminated) {
        dealt.add(player.copyWith(hand: const []));
      } else {
        dealt.add(player.copyWith(hand: const []));
      }
    }
    for (var cardIndex = 0; cardIndex < 5; cardIndex++) {
      for (var i = 0; i < dealt.length; i++) {
        if (dealt[i].isEliminated) continue;
        dealt[i] = dealt[i].copyWith(hand: [...dealt[i].hand, deck.removeLast()]);
      }
    }
    var firstIndex = dealt.indexWhere((player) => !player.isEliminated && player.id == starterId);
    if (firstIndex < 0) firstIndex = dealt.indexWhere((player) => !player.isEliminated);
    return GameState(
      players: dealt,
      drawPile: deck,
      discardPile: const [],
      currentPlayerIndex: firstIndex,
      targetScore: previousState.targetScore,
      phase: GamePhase.waitingForTurn,
      roundNumber: previousState.roundNumber + 1,
    );
  }

  List<PlayingCard> _newDeck() => [
    for (final suit in CardSuit.values)
      for (final rank in CardRank.values)
        PlayingCard(rank: rank, suit: suit),
  ];

  TurnResult discardAndDraw({
    required GameState state,
    required String playerId,
    required List<PlayingCard> cardsToDiscard,
    required DrawSource drawSource,
  }) {
    _ensureActiveTurn(state, playerId);
    if (cardsToDiscard.isEmpty) throw ArgumentError('At least one card must be discarded.');
    if (cardsToDiscard.any((card) => card.rank == CardRank.nine)) {
      throw StateError('A 9 (नौकी) can never be discarded.');
    }
    if (cardsToDiscard.map((card) => card.rank).toSet().length != 1) {
      throw StateError('Only one card or a same-rank group can be discarded.');
    }

    final player = state.currentPlayer;
    final remainingHand = [...player.hand];
    for (final card in cardsToDiscard) {
      if (!remainingHand.remove(card)) throw StateError('A discarded card is not present in this hand.');
    }
    final updatedPlayers = [...state.players];
    updatedPlayers[state.currentPlayerIndex] = player.copyWith(hand: remainingHand);
    final updatedDiscard = [...state.discardPile, ...cardsToDiscard];
    var updatedDrawPile = [...state.drawPile];
    var reshuffled = false;

    late final PlayingCard drawnCard;
    if (drawSource == DrawSource.drawPile) {
      if (updatedDrawPile.isEmpty) {
        updatedDrawPile = [...updatedDiscard]..shuffle(_random);
        updatedDiscard.clear();
        reshuffled = true;
      }
      drawnCard = updatedDrawPile.removeLast();
    } else {
      final previousIndex = _previousActivePlayerIndex(state);
      final previousPlayer = state.players[previousIndex];
      if (state.lastDiscardPlayerId != previousPlayer.id || state.lastDiscardGroup.isEmpty) {
        throw StateError('No eligible discard from the immediately previous player.');
      }
      final available = [...state.lastDiscardGroup];
      drawnCard = available.removeLast();
      updatedDiscard.remove(drawnCard);
    }

    updatedPlayers[state.currentPlayerIndex] = updatedPlayers[state.currentPlayerIndex]
        .copyWith(hand: [...updatedPlayers[state.currentPlayerIndex].hand, drawnCard]);

    final nextState = state.copyWith(
      players: updatedPlayers,
      drawPile: updatedDrawPile,
      discardPile: updatedDiscard,
      lastDiscardPlayerId: player.id,
      lastDiscardGroup: reshuffled ? const [] : cardsToDiscard,
      lastDiscardPlayerId: reshuffled ? null : player.id,
    );

    if (nextState.currentPlayer.handTotal == 0) {
      final round = resolveShow(nextState, playerId, wasAutomatic: true);
      return TurnResult(
        state: nextState.copyWith(
          players: round.updatedPlayers,
          phase: round.winnerId == null ? GamePhase.roundComplete : GamePhase.gameComplete,
          winnerId: round.winnerId,
        ),
        roundResult: round,
      );
    }
    final advanced = nextState.copyWith(
      currentPlayerIndex: _nextActivePlayerIndex(nextState, state.currentPlayerIndex),
    );
    if (advanced.currentPlayer.handTotal == 0) {
      final result = resolveShow(advanced, advanced.currentPlayer.id, wasAutomatic: true);
      return TurnResult(
        state: advanced.copyWith(
          players: result.updatedPlayers,
          phase: result.winnerId == null ? GamePhase.roundComplete : GamePhase.gameComplete,
          winnerId: result.winnerId,
        ),
        roundResult: result,
      );
    }
    return TurnResult(state: advanced);
  }

  TurnResult show(GameState state, String callerId) {
    final round = resolveShow(state, callerId);
    return TurnResult(
      state: state.copyWith(
        players: round.updatedPlayers,
        phase: round.winnerId == null ? GamePhase.roundComplete : GamePhase.gameComplete,
        winnerId: round.winnerId,
      ),
      roundResult: round,
    );
  }

  RoundResult resolveShow(GameState state, String callerId, {bool wasAutomatic = false}) {
    _ensureActiveTurn(state, callerId);
    final activePlayers = state.players.where((p) => !p.isEliminated).toList();
    final caller = state.playerById(callerId)!;
    final totals = {for (final p in activePlayers) p.id: p.handTotal};
    final callerTotal = caller.handTotal;
    final successful = activePlayers.where((p) => p.id != callerId).every((p) => p.handTotal > callerTotal);

    final points = <String, int>{for (final p in activePlayers) p.id: 0};
    if (successful) {
      for (final p in activePlayers) {
        if (p.id != callerId) points[p.id] = p.handTotal;
      }
    } else {
      points[callerId] = totals.values.fold(0, (sum, value) => sum + value);
    }

    final updatedPlayers = <PlayerState>[];
    final eliminated = <String>[];
    for (final p in state.players) {
      if (p.isEliminated) {
        updatedPlayers.add(p);
        continue;
      }
      final newScore = p.score + (points[p.id] ?? 0);
      final isOut = newScore >= state.targetScore;
      if (isOut) eliminated.add(p.id);
      updatedPlayers.add(p.copyWith(score: newScore, isEliminated: isOut));
    }
    final remaining = updatedPlayers.where((p) => !p.isEliminated).toList();
    return RoundResult(
      callerId: callerId,
      callerHandTotal: callerTotal,
      wasSuccessful: successful,
      handTotals: Map.unmodifiable(totals),
      pointsAdded: Map.unmodifiable(points),
      eliminatedPlayerIds: List.unmodifiable(eliminated),
      updatedPlayers: List.unmodifiable(updatedPlayers),
      winnerId: remaining.length == 1 ? remaining.single.id : null,
      wasAutomatic: wasAutomatic,
    );
  }

  void _ensureActiveTurn(GameState state, String playerId) {
    if (state.phase != GamePhase.waitingForTurn) throw StateError('The round is not accepting turns.');
    if (state.currentPlayer.id != playerId) throw StateError('It is not this player\'s turn.');
    if (state.currentPlayer.isEliminated) throw StateError('An eliminated player cannot take a turn.');
  }

  int _previousActivePlayerIndex(GameState state) {
    var index = state.currentPlayerIndex;
    for (var attempts = 0; attempts < state.players.length; attempts++) {
      index = (index - 1 + state.players.length) % state.players.length;
      if (!state.players[index].isEliminated) return index;
    }
    throw StateError('No previous active player.');
  }

  int _nextActivePlayerIndex(GameState state, int fromIndex) {
    var index = fromIndex;
    for (var attempts = 0; attempts < state.players.length; attempts++) {
      index = (index + 1) % state.players.length;
      if (!state.players[index].isEliminated) return index;
    }
    return fromIndex;
  }
}

class TurnResult {
  const TurnResult({required this.state, this.roundResult});
  final GameState state;
  final RoundResult? roundResult;
}
