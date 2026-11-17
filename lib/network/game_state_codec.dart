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
    'revealHands': revealHands,
  };

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
