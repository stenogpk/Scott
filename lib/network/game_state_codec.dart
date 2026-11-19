import '../game/game_models.dart';
import '../game/playing_card.dart';

class GameStateCodec {
  static Map<String, dynamic> publicState(GameState state, {bool revealHands = false}) => {
    'players': [
      for (final player in state.players)
        {
          'id': player.id,
          'name': player.name,
          'score': player.score,
          'isEliminated': player.isEliminated,
          'handCount': player.hand.length,
          if (revealHands) 'handTotal': player.handTotal,
          if (revealHands) 'hand': player.hand.map(cardToJson).toList(),
        },
    ],
    'currentPlayerId': state.currentPlayer.id,
    'drawPileCount': state.drawPile.length,
    'discardPile': state.discardPile.map(cardToJson).toList(),
    'lastDiscardPlayerId': state.lastDiscardPlayerId,
    'lastDiscardGroup': state.lastDiscardGroup.map(cardToJson).toList(),
    'targetScore': state.targetScore,
    'phase': state.phase.name,
    'roundNumber': state.roundNumber,
    'winnerId': state.winnerId,
    'missedTurnCounts': state.missedTurnCounts,
    'revealHands': revealHands,
  };

  static Map<String, dynamic> hostRecovery(GameState state, {List<Map<String, dynamic>> history = const [], String? commentary}) => {
    'state': publicState(state, revealHands: true),
    'drawPile': state.drawPile.map(cardToJson).toList(),
    'history': history,
    'commentary': commentary,
  };

  static GameState stateFromHostRecovery(Map<String, dynamic> recovery) {
    final raw = Map<String, dynamic>.from(recovery['state'] as Map);
    final players = (raw['players'] as List).map((value) {
      final p = Map<String, dynamic>.from(value as Map);
      final hand = (p['hand'] as List? ?? const []).map((card) => cardFromJson(Map<String, dynamic>.from(card as Map))).toList();
      return PlayerState(
        id: p['id'] as String,
        name: p['name'] as String,
        hand: hand,
        score: p['score'] as int? ?? 0,
        isEliminated: p['isEliminated'] as bool? ?? false,
      );
    }).toList();
    final currentId = raw['currentPlayerId'] as String;
    final currentIndex = players.indexWhere((p) => p.id == currentId);
    if (currentIndex < 0) throw StateError('Host recovery में current player नहीं मिला।');
    return GameState(
      players: players,
      drawPile: (recovery['drawPile'] as List).map((v) => cardFromJson(Map<String, dynamic>.from(v as Map))).toList(),
      discardPile: (raw['discardPile'] as List? ?? const []).map((v) => cardFromJson(Map<String, dynamic>.from(v as Map))).toList(),
      currentPlayerIndex: currentIndex,
      targetScore: raw['targetScore'] as int,
      phase: GamePhase.values.byName(raw['phase'] as String),
      winnerId: raw['winnerId'] as String?,
      lastDiscardPlayerId: raw['lastDiscardPlayerId'] as String?,
      lastDiscardGroup: (raw['lastDiscardGroup'] as List? ?? const []).map((v) => cardFromJson(Map<String, dynamic>.from(v as Map))).toList(),
      roundNumber: raw['roundNumber'] as int? ?? 1,
      missedTurnCounts: Map<String, int>.from((raw['missedTurnCounts'] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),),
    );
  }

  static Map<String, List<Map<String, dynamic>>> privateHands(GameState state) => {
    for (final player in state.players)
      player.id: player.hand.map(cardToJson).toList(),
  };

  static Map<String, dynamic> cardToJson(PlayingCard card) => {
    'rank': card.rank.name,
    'suit': card.suit.name,
  };

  static PlayingCard cardFromJson(Map<String, dynamic> json) => PlayingCard(
    rank: CardRank.values.byName(json['rank'] as String),
    suit: CardSuit.values.byName(json['suit'] as String),
  );
}
