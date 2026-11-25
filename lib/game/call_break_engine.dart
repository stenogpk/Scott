import 'dart:math';
import '../game/playing_card.dart';
class CallBreakPlayer {
  CallBreakPlayer(this.id,this.name,{this.isBot=false});
  final String id,name; final bool isBot;
  int bid=0,tricks=0; double score=0; List<PlayingCard> hand=[];
}
class CallBreakEngine {
  CallBreakEngine({Random? random}):_random=random??Random();
  final Random _random;
  final List<CallBreakPlayer> players=[CallBreakPlayer('you','आप'),CallBreakPlayer('bot1','खिलाड़ी 2',isBot:true),CallBreakPlayer('bot2','खिलाड़ी 3',isBot:true),CallBreakPlayer('bot3','खिलाड़ी 4',isBot:true)];
  int round=1,dealer=0,turn=0,trickLead=0,trickNumber=0;
  CardSuit? leadSuit; final List<({int player,PlayingCard card})> trick=[]; bool complete=false;
  static int power(PlayingCard c)=>c.rank==CardRank.ace?14:c.rank.index+1;
  static int _sort(PlayingCard a,PlayingCard b)=>a.suit.index.compareTo(b.suit.index).sign==0?power(a).compareTo(power(b)):a.suit.index.compareTo(b.suit.index);
  void deal(){
    final deck=[for(final s in CardSuit.values)for(final r in CardRank.values)PlayingCard(rank:r,suit:s)]..shuffle(_random);
    for(var i=0;i<4;i++){players[i].hand=deck.sublist(i*13,(i+1)*13)..sort(_sort);players[i].bid=0;players[i].tricks=0;}
    trick.clear();trickNumber=0;leadSuit=null;turn=(dealer+1)%4;trickLead=turn;complete=false;
  }
  int estimate(List<PlayingCard> hand){final spades=hand.where((c)=>c.suit==CardSuit.spades).length;final high=hand.where((c)=>power(c)>=11).length;return (spades*.55+high*.45).round().clamp(1,8).toInt();}
  int get totalBids=>players.fold(0,(s,p)=>s+p.bid);
  bool get bidding=>players.any((p)=>p.bid==0);
  void setBid(int player,int bid){
    if(player!=turn||players[player].bid!=0||bid<1||bid>13)throw StateError('अभी इस खिलाड़ी की बोली का समय नहीं है।');
    players[player].bid=bid;turn=(turn+1)%4;
    if(players.every((p)=>p.bid>0)){if(totalBids<9){for(final p in players){p.bid=0;}turn=(dealer+1)%4;throw StateError('कुल बोली 9 से कम है। दोबारा बोली लगाएँ।');}turn=(dealer+1)%4;trickLead=turn;}
  }
  List<PlayingCard> legalCards(int player){final hand=players[player].hand;if(leadSuit==null)return hand;final follow=hand.where((c)=>c.suit==leadSuit).toList();return follow.isEmpty?hand:follow;}
  void play(int player,PlayingCard card){
    if(bidding||complete||player!=turn)throw StateError('अभी इस खिलाड़ी की चाल नहीं है।');
    if(!legalCards(player).contains(card))throw StateError('पहले उसी रंग का पत्ता चलें।');
    players[player].hand.remove(card);leadSuit??=card.suit;trick.add((player:player,card:card));
    if(trick.length<4){turn=(turn+1)%4;return;}
    final winner=_winner();players[winner].tricks++;trickNumber++;trick.clear();leadSuit=null;trickLead=winner;turn=winner;
    if(trickNumber==13){for(final p in players){final extra=p.tricks-p.bid;if(extra<0||p.tricks>p.bid*2){p.score-=p.bid.toDouble();}else{p.score+=p.bid+(extra/10);}}complete=true;}
  }
  int _winner(){var best=trick.first;for(final play in trick.skip(1)){final c=play.card,b=best.card;final beats=(c.suit==CardSuit.spades&&b.suit!=CardSuit.spades)||(c.suit==b.suit&&power(c)>power(b));if(beats)best=play;}return best.player;}
  void nextRound(){round++;dealer=(dealer+1)%4;deal();}
  String winnerName()=>players.reduce((a,b)=>a.score>=b.score?a:b).name;
}
