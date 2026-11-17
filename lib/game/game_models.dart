import 'playing_card.dart';

enum GamePhase { waitingForTurn, roundComplete, gameComplete }
enum DrawSource { drawPile, previousPlayerDiscard }

class PlayerState {
  PlayerState({
    required this.id,
    required this.name,
    List<PlayingCard> hand = const [],
    this.score = 0,
    this.isEliminated = false,
  }) : hand = List.unmodifiable(hand);

  final String id;
  final String name;
  final List<PlayingCard> hand;
  final int score;
  final bool isEliminated;

  int get handTotal => hand.fold(0, (sum, card) => sum + card.value);

  PlayerState copyWith({List<PlayingCard>? hand, int? score, bool? isEliminated}) =>
      PlayerState(
        id: id,
        name: name,
        hand: hand ?? this.hand,
        score: score ?? this.score,
        isEliminated: isEliminated ?? this.isEliminated,
      );
}

class GameState {
  GameState({
    required List<PlayerState> players,
    required List<PlayingCard> drawPile,
    required List<PlayingCard> discardPile,
    required this.currentPlayerIndex,
    required this.targetScore,
    required this.phase,
    this.winnerId,
    this.lastDiscardPlayerId,
    List<PlayingCard> lastDiscardGroup = const [],
    this.roundNumber = 1,
  }) : players = List.unmodifiable(players),
       drawPile = List.unmodifiable(drawPile),
       discardPile = List.unmodifiable(discardPile),
       lastDiscardGroup = List.unmodifiable(lastDiscardGroup);

  final List<PlayerState> players;
  final List<PlayingCard> drawPile;
  final List<PlayingCard> discardPile;
  final int currentPlayerIndex;
  final int targetScore;
  final GamePhase phase;
  final String? winnerId;
  final String? lastDiscardPlayerId;
  final List<PlayingCard> lastDiscardGroup;
  final int roundNumber;

  PlayerState get currentPlayer => players[currentPlayerIndex];

  PlayerState? playerById(String id) {
    for (final player in players) {
      if (player.id == id) return player;
    }
    return null;
  }

  GameState copyWith({
    List<PlayerState>? players,
    List<PlayingCard>? drawPile,
    List<PlayingCard>? discardPile,
    int? currentPlayerIndex,
    GamePhase? phase,
    String? winnerId,
    String? lastDiscardPlayerId,
    List<PlayingCard>? lastDiscardGroup,
    int? roundNumber,
  }) => GameState(
    players: players ?? this.players,
    drawPile: drawPile ?? this.drawPile,
    discardPile: discardPile ?? this.discardPile,
    currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
    targetScore: targetScore,
    phase: phase ?? this.phase,
    winnerId: winnerId ?? this.winnerId,
    lastDiscardPlayerId: lastDiscardPlayerId ?? this.lastDiscardPlayerId,
    lastDiscardGroup: lastDiscardGroup ?? this.lastDiscardGroup,
    roundNumber: roundNumber ?? this.roundNumber,
  );
}

class RoundResult {
  const RoundResult({
    required this.callerId,
    required this.callerHandTotal,
    required this.wasSuccessful,
    required this.handTotals,
    required this.pointsAdded,
    required this.eliminatedPlayerIds,
    required this.updatedPlayers,
    this.winnerId,
    this.wasAutomatic = false,
  });

  final String callerId;
  final int callerHandTotal;
  final bool wasSuccessful;
  final Map<String, int> handTotals;
  final Map<String, int> pointsAdded;
  final List<String> eliminatedPlayerIds;
  final List<PlayerState> updatedPlayers;
  final String? winnerId;
  final bool wasAutomatic;
}
