import 'package:flutter/material.dart';
import '../game/playing_card.dart';
import '../game/call_break_engine.dart';

class CallBreakPage extends StatefulWidget {
  const CallBreakPage({super.key});
  @override State<CallBreakPage> createState()=>_CallBreakPageState();
}
class _CallBreakPageState extends State<CallBreakPage> {
  late CallBreakEngine game;
  int rounds=5;
  int selectedBid=2;
  String? notice;
  @override void initState(){super.initState();_newMatch();}
  void _newMatch(){game=CallBreakEngine();game.deal();_runBots();}
  void _runBots(){
    while(mounted && !game.complete && game.turn!=0){
      if(game.bidding){
        final p=game.players[game.turn];
        try{game.setBid(game.turn,game.players[game.turn].isBot? _botBid(p.hand):selectedBid);}catch(_){game.setBid(game.turn,2);}
      }else{
        final legal=game.legalCards(game.turn);
        legal.sort((a,b)=>a.rank.index.compareTo(b.rank.index));
        game.play(game.turn,legal.first);
      }
    }
    if(mounted)setState((){});
  }
  int _botBid(List<PlayingCard> hand){
    final spades=hand.where((c)=>c.suit==CardSuit.spades).length;
    final high=hand.where((c)=>c.rank.index>=10).length;
    return (spades*.55+high*.45).round().clamp(1,6).toInt();
  }
  void _bid(int bid){
    try{game.setBid(0,bid);notice=null;_runBots();}
    catch(e){notice=e.toString();setState((){});}
  }
  void _play(PlayingCard card){
    try{game.play(0,card);notice=null;_runBots();}
    catch(e){notice=e.toString();setState((){});}
  }
  String _cardLabel(PlayingCard c)=>'${c.rank.shortLabel}${c.suit.symbol}';
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('लकड़ी • CALL BREAK'),actions:[IconButton(onPressed:()=>showModalBottomSheet(context:context,builder:(_)=>_rules()),icon:const Icon(Icons.menu_book_outlined))]),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(14),children:[
      Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF142B45),borderRadius:BorderRadius.circular(18)),child:Column(children:[
        const Text('CALL BREAK',style:TextStyle(color:Color(0xFFD9B76E),fontSize:22,fontWeight:FontWeight.w900,letterSpacing:2)),
        const SizedBox(height:8),Text('राउंड ${game.round} / $rounds  •  चाल ${game.trickNumber+1}/13',style:const TextStyle(color:Colors.white)),
        const SizedBox(height:8),Text(game.complete?'राउंड पूरा • अगला राउंड शुरू करें':game.bidding?'बोली का समय':'चाल: ${game.players[game.turn].name}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
      ])),
      const SizedBox(height:12),
      Row(children:[const Text('मैच राउंड',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),DropdownButton<int>(value:rounds,items:[for(int n=5;n<=13;n++)DropdownMenuItem(value:n,child:Text('$n'))],onChanged:(v)=>setState(()=>rounds=v!))]),
      Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
        for(int i=0;i<4;i++)ListTile(dense:true,leading:CircleAvatar(child:Text('${i+1}')),title:Text(game.players[i].name),subtitle:Text('बोली: ${game.players[i].bid==0?'—':game.players[i].bid}  •  ट्रिक: ${game.players[i].tricks}'),trailing:Text(game.players[i].score.toStringAsFixed(1),style:const TextStyle(fontWeight:FontWeight.w900))),
      ]))),
      if(notice!=null)Padding(padding:const EdgeInsets.all(8),child:Text(notice!,style:const TextStyle(color:Colors.red))),
      if(game.bidding && game.turn==0)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
        const Text('अपनी बोली चुनें (1–13)',style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:6,children:[for(int n=1;n<=13;n++)ChoiceChip(label:Text('$n'),selected:selectedBid==n,onSelected:(_)=>setState(()=>selectedBid=n))]),
        const SizedBox(height:8),FilledButton(onPressed:()=>_bid(selectedBid),child:const Text('बोली पक्की करें')),
      ]))),
      if(!game.bidding && !game.complete)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        const Text('आपके पत्ते',style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:6,runSpacing:6,children:[for(final c in game.players[0].hand)ActionChip(label:Text(_cardLabel(c),style:TextStyle(color:c.suit.isRed?Colors.red:Colors.black,fontWeight:FontWeight.bold)),onPressed:game.turn==0 && game.legalCards(0).contains(c)?()=>_play(c):null)]),
        const SizedBox(height:8),Text('टेबल पर: ${game.trick.map((e)=>'${game.players[e.player].name}: ${_cardLabel(e.card)}').join('   ')}'),
      ]))),
      if(game.complete)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        const Text('राउंड स्कोर',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        for(final p in game.players)ListTile(title:Text(p.name),subtitle:Text('बोली ${p.bid} • जीतीं ${p.tricks} ट्रिक'),trailing:Text(p.score.toStringAsFixed(1))),
        if(game.round>=rounds)Text('मैच विजेता: ${game.winnerName()}',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),
        FilledButton(onPressed:game.round>=rounds?()=>setState(_newMatch):()=>setState(()=>game.nextRound()),child:Text(game.round>=rounds?'नया मैच':'अगला राउंड')),
      ]))),
      const SizedBox(height:18),const Center(child:Text('Developed by Shartendu',style:TextStyle(color:Colors.blueGrey,fontSize:11))),
    ])));
  Widget _rules()=>const SafeArea(child:Padding(padding:EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('खेल के नियम',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    Text('चार खिलाड़ी • 52 पत्ते • हर खिलाड़ी को 13 पत्ते। स्पेड (♠) हमेशा ट्रम्प है। हर खिलाड़ी 1 से 13 तक बोली लगाता है। सभी की कुल बोली कम-से-कम 9 होनी चाहिए; कम होने पर बोली दोबारा होगी।'),
    SizedBox(height:10),Text('बोली पूरी करने पर 13 ट्रिक खेली जाती हैं। पहले चलाए गए रंग का पत्ता देना जरूरी है; रंग न हो तो कोई भी पत्ता चल सकते हैं। ट्रम्प पत्ता ट्रिक जीतता है।'),
    SizedBox(height:10),Text('बोली पूरी न होने पर बोली के बराबर अंक कटेंगे। बोली से अधिक ट्रिक पर हर अतिरिक्त ट्रिक का 0.1 बोनस मिलेगा; बोली से दोगुने से अधिक ट्रिक पर बोली के बराबर अंक कटेंगे।'),
  ]))));
}
