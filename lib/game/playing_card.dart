enum CardSuit { hearts, diamonds, clubs, spades }

enum CardRank { ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king }

extension CardRankValue on CardRank {
  int get value => switch (this) {
    CardRank.ace => 1,
    CardRank.two => 2,
    CardRank.three => 3,
    CardRank.four => 4,
    CardRank.five => 5,
    CardRank.six => 6,
    CardRank.seven => 7,
    CardRank.eight => 8,
    CardRank.nine => 0,
    CardRank.ten => 10,
    CardRank.jack => 11,
    CardRank.queen => 12,
    CardRank.king => 13,
  };

  String get shortLabel => switch (this) {
    CardRank.ace => 'A',
    CardRank.two => '2',
    CardRank.three => '3',
    CardRank.four => '4',
    CardRank.five => '5',
    CardRank.six => '6',
    CardRank.seven => '7',
    CardRank.eight => '8',
    CardRank.nine => '9',
    CardRank.ten => '10',
    CardRank.jack => 'J',
    CardRank.queen => 'Q',
    CardRank.king => 'K',
  };
}

extension CardSuitSymbol on CardSuit {
  String get symbol => switch (this) {
    CardSuit.hearts => '♥',
    CardSuit.diamonds => '♦',
    CardSuit.clubs => '♣',
    CardSuit.spades => '♠',
  };

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;
}

class PlayingCard {
  const PlayingCard({required this.rank, required this.suit});
  final CardRank rank;
  final CardSuit suit;
  int get value => rank.value;

  @override
  bool operator ==(Object other) => other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  @override
  String toString() => '${rank.shortLabel}${suit.symbol}';
}
