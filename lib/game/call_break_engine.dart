import 'dart:math';
import 'playing_card.dart';

class CallBreakPlayer {
  CallBreakPlayer(this.id, this.name, {this.isBot = false});
  final String id;
  final String name;
  final bool isBot;
  int bid = 0;
  int tricks = 0;
  double score = 0;
  List<PlayingCard> hand = [];
}

class CallBreakEngine {
  CallBreakEngine({required List<({String id, String name, bool isBot})> seats, Random? random})
      : _random = random ?? Random(),
        players = seats.map((p) => CallBreakPlayer(p.id, p.name, isBot: p.isBot)).toList() {
    if (players.length != 4) throw ArgumentError('Call Break में चार खिलाड़ी जरूरी हैं।');
  }

  final Random _random;
  final List<CallBreakPlayer> players;
  int round = 1;
  int dealer = 0;
  int turn = 0;
  int trickLead = 0;
  int trickNumber = 0;
  int roundsToPlay = 5;
  CardSuit? leadSuit;
  final List<({int player, PlayingCard card})> trick = [];
  final List<Map<String, dynamic>> roundHistory = [];
  List<({int player, PlayingCard card})> lastTrick = [];
  int? lastTrickWinner;
  bool complete = false;
  bool redealRequired = false;

  static int power(PlayingCard c) => c.rank == CardRank.ace ? 14 : c.rank.index + 1;
  static int _sort(PlayingCard a, PlayingCard b) {
    final suit = a.suit.index.compareTo(b.suit.index);
    return suit == 0 ? power(a).compareTo(power(b)) : suit;
  }

  int get totalBids => players.fold(0, (sum, p) => sum + p.bid);
  bool get bidding => players.any((p) => p.bid == 0);
  bool get matchComplete => round >= roundsToPlay && complete;
  String get winnerName => players.reduce((a, b) => a.score >= b.score ? a : b).name;

  void deal() {
    final deck = [for (final s in CardSuit.values) for (final r in CardRank.values) PlayingCard(rank: r, suit: s)]..shuffle(_random);
    for (var i = 0; i < 4; i++) {
      players[i].hand = deck.sublist(i * 13, (i + 1) * 13)..sort(_sort);
      players[i].bid = 0;
      players[i].tricks = 0;
    }
    trick.clear();
    lastTrick = [];
    lastTrickWinner = null;
    trickNumber = 0;
    leadSuit = null;
    complete = false;
    redealRequired = false;
    turn = (dealer + 1) % 4;
    trickLead = turn;
  }

  int estimate(List<PlayingCard> hand) {
    final spades = hand.where((c) => c.suit == CardSuit.spades).length;
    final aces = hand.where((c) => c.rank == CardRank.ace).length;
    final kings = hand.where((c) => c.rank == CardRank.king).length;
    final queens = hand.where((c) => c.rank == CardRank.queen).length;
    return (spades * .45 + aces + kings * .65 + queens * .35).round().clamp(1, 8).toInt();
  }

  void setBid(int player, int bid) {
    if (!bidding || player != turn || players[player].bid != 0 || bid < 1 || bid > 13) {
      throw StateError('अभी इस खिलाड़ी की बोली का समय नहीं है।');
    }
    players[player].bid = bid;
    turn = (turn + 1) % 4;
    if (!bidding && totalBids < 9) {
      for (final p in players) { p.bid = 0; }
      turn = (dealer + 1) % 4;
      redealRequired = true;
      throw StateError('कुल बोली 9 से कम है। सभी खिलाड़ी दोबारा बोली लगाएँ।');
    }
    if (!bidding) {
      turn = (dealer + 1) % 4;
      trickLead = turn;
    }
  }

  List<PlayingCard> legalCards(int player) {
    return legalCardsForHand(
      players[player].hand,
      leadSuit: leadSuit,
      trick: trick,
    );
  }

  /// Call Break follow-suit rule: if a player can overtake the highest
  /// card currently played in the led suit, they must play a higher card.
  /// Any higher card is valid; playing the highest available card is not
  /// required. If none can overtake, any card of the led suit is valid.
  /// When void in the led suit, any card (including an optional spade cut)
  /// may be played.
  static List<PlayingCard> legalCardsForHand(
    List<PlayingCard> hand, {
    required CardSuit? leadSuit,
    required List<({int player, PlayingCard card})> trick,
  }) {
    if (leadSuit == null) return List.of(hand);
    final follow = hand.where((c) => c.suit == leadSuit).toList();
    if (follow.isEmpty) return List.of(hand);

    final highestInLeadSuit = trick
        .where((play) => play.card.suit == leadSuit)
        .fold<int>(0, (best, play) =>
            power(play.card) > best ? power(play.card) : best);
    if (highestInLeadSuit == 0) return follow;

    final higher = follow
        .where((card) => power(card) > highestInLeadSuit)
        .toList();
    return higher.isNotEmpty ? higher : follow;
  }

  void play(int player, PlayingCard card) {
    if (bidding || complete || player != turn) throw StateError('अभी इस खिलाड़ी की चाल नहीं है।');
    if (!legalCards(player).contains(card)) throw StateError('पहले उसी रंग का पत्ता चलें।');
    players[player].hand.remove(card);
    leadSuit ??= card.suit;
    trick.add((player: player, card: card));
    if (trick.length < 4) { turn = (turn + 1) % 4; return; }
    final winner = _winner();
    lastTrick = List.of(trick);
    lastTrickWinner = winner;
    players[winner].tricks++;
    trickNumber++;
    trick.clear();
    leadSuit = null;
    trickLead = winner;
    turn = winner;
    if (trickNumber == 13) {
      final roundPlayers = <Map<String, dynamic>>[];
      for (final p in players) {
        final extra = p.tricks - p.bid;
        final roundScore = (extra < 0 || p.tricks > p.bid * 2)
            ? -p.bid.toDouble()
            : p.bid + extra / 10;
        p.score += roundScore;
        roundPlayers.add({
          'id': p.id, 'name': p.name, 'bid': p.bid,
          'tricks': p.tricks, 'roundScore': roundScore, 'totalScore': p.score,
        });
      }
      roundHistory.add({'round': round, 'players': roundPlayers});
      complete = true;
    }
  }

  int _winner() {
    var best = trick.first;
    for (final play in trick.skip(1)) {
      final c = play.card, b = best.card;
      final beats = (c.suit == CardSuit.spades && b.suit != CardSuit.spades) ||
          (c.suit == b.suit && power(c) > power(b));
      if (beats) best = play;
    }
    return best.player;
  }

  void nextRound() {
    if (!complete || matchComplete) throw StateError('अगला राउंड उपलब्ध नहीं है।');
    round++;
    dealer = (dealer + 1) % 4;
    deal();
  }

  Map<String, dynamic> publicState() => {
    'round': round, 'roundsToPlay': roundsToPlay, 'dealer': dealer, 'turn': turn,
    'trickLead': trickLead, 'trickNumber': trickNumber, 'leadSuit': leadSuit?.name,
    'complete': complete, 'bidding': bidding, 'totalBids': totalBids,
    'roundHistory': roundHistory,
    'redealRequired': redealRequired, 'winnerName': winnerName,
    'players': [for (final p in players) {
      'id': p.id, 'name': p.name, 'isBot': p.isBot, 'bid': p.bid,
      'tricks': p.tricks, 'score': p.score, 'handCount': p.hand.length,
    }],
    'trick': [for (final t in trick) {'player': t.player, 'card': cardToJson(t.card)}],
    'lastTrick': [for (final t in lastTrick) {'player': t.player, 'card': cardToJson(t.card)}],
    'lastTrickWinner': lastTrickWinner,
  };

  Map<String, List<Map<String, dynamic>>> privateHands() => {
    for (final p in players) p.id: p.hand.map(cardToJson).toList(),
  };

  static Map<String, dynamic> cardToJson(PlayingCard c) => {'rank': c.rank.name, 'suit': c.suit.name};
  static PlayingCard cardFromJson(Map<String, dynamic> j) => PlayingCard(
    rank: CardRank.values.byName(j['rank'] as String),
    suit: CardSuit.values.byName(j['suit'] as String),
  );
}
