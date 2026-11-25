import 'dart:async';
// ignore_for_file: deprecated_member_use, prefer_is_empty
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/firebase_room_service.dart';
import '../network/room_models.dart';
import '../game/call_break_engine.dart';
import '../game/playing_card.dart';
import '../services/voice_chat_panel.dart';

const _cbApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _cbDatabaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

class CallBreakOnlinePage extends StatefulWidget {
  const CallBreakOnlinePage({super.key});
  @override State<CallBreakOnlinePage> createState() => _CallBreakOnlinePageState();
}

class _CallBreakOnlinePageState extends State<CallBreakOnlinePage> {
  final _name = TextEditingController();
  final _code = TextEditingController(text: Uri.base.queryParameters['room'] ?? '');
  late final FirebaseRoomService _service = FirebaseRoomService(apiKey: _cbApiKey, databaseUrl: _cbDatabaseUrl);
  RoomSnapshot? _room;
  StreamSubscription<RoomSnapshot>? _roomSub;
  StreamSubscription<Map<String, dynamic>>? _gameSub;
  bool _busy = false;
  bool _fillBots = true;
  String? _error;
  int _rounds = 5;
  bool _opened = false;

  @override
  void dispose() {
    _name.dispose(); _code.dispose();
    unawaited(_roomSub?.cancel()); unawaited(_gameSub?.cancel()); unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _run(Future<RoomSnapshot> Function() task) async {
    if (_name.text.trim().isEmpty) { setState(() => _error = 'पहले अपना नाम लिखें।'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final room = await task();
      if (!mounted) return;
      setState(() { _room = room; _busy = false; });
      _watchRoom(room.code);
      if (room.hostId != _service.userId) _watchGame(room.code);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Bad state: ', ''); _busy = false; });
    }
  }

  Future<void> _create() => _run(() => _service.createRoom(playerName: _name.text.trim(), targetScore: 13));
  Future<void> _join() async {
    await _run(() async {
      final room = await _service.getRoom(_code.text.trim().toUpperCase());
      if (room.players.length >= 4) throw StateError('इस Room में चारों सीटें भर चुकी हैं।');
      return _service.joinRoom(code: _code.text.trim().toUpperCase(), playerName: _name.text.trim(), maxPlayers: 4);
    });
  }

  void _watchRoom(String code) {
    _roomSub?.cancel();
    _roomSub = _service.watchRoom(code).listen((room) {
      if (!mounted) return;
      if (room.players.length > 4) { setState(() => _error = 'Room में अधिकतम चार खिलाड़ी ही हो सकते हैं।'); return; }
      setState(() => _room = room);
    }, onError: (e) { if (mounted) setState(() => _error = e.toString()); });
  }

  void _watchGame(String code) {
    _gameSub?.cancel();
    _gameSub = _service.watchGame(code).listen((message) {
      if (!mounted || _opened || message['type'] != 'game') return;
      _opened = true;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CallBreakGuestTable(
        roomCode: code, playerId: _service.userId!, initial: message,
        messages: _service.watchGame(code), sendAction: (action) => _service.sendAction(code, action),
        getToken: _service.getCurrentIdToken,
      )));
    }, onError: (e) { if (mounted) setState(() => _error = e.toString()); });
  }

  Future<void> _start() async {
    final room = _room;
    if (room == null || room.hostId != _service.userId) return;
    if (room.players.isEmpty || (!_fillBots && room.players.length != 4)) {
      setState(() => _error = 'बिना Bots के शुरू करने के लिए चारों खिलाड़ियों का जुड़ना जरूरी है।'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final seats = <({String id, String name, bool isBot})>[
        for (final p in room.players) (id: p.id, name: p.name, isBot: false),
      ];
      var bot = 1;
      while (seats.length < 4) { seats.add((id: 'bot_$bot', name: 'Bot $bot', isBot: true)); bot++; }
      final engine = CallBreakEngine(seats: seats)..roundsToPlay = _rounds;
      engine.deal();
      await _service.publishGameState(room.code, engine.publicState(), engine.privateHands());
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CallBreakHostTable(
        roomCode: room.code, engine: engine, service: _service,
      )));
    } catch (e) { if (mounted) setState(() { _busy = false; _error = e.toString(); }); }
  }

  String get _inviteUrl => 'https://stenogpk.github.io/Scott/voice-test/?callbreak=1&room=${_room?.code ?? _code.text.trim().toUpperCase()}';
  String get _inviteText => 'लकड़ी • CALL BREAK में मेरे साथ खेलें!\nRoom Code: ${_room?.code ?? _code.text.trim().toUpperCase()}\nइस लिंक को ब्राउज़र में खोलें, अपना नाम लिखें और Join Room दबाएँ:\n$_inviteUrl';

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: _inviteText));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite कॉपी हो गया।')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('लकड़ी • CALL BREAK')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF142B45), Color(0xFF247A83)]), borderRadius: BorderRadius.circular(20)), child: const Column(children: [
        Icon(Icons.style, color: Color(0xFFD9B76E), size: 42),
        SizedBox(height: 8), Text('CALL BREAK', style: TextStyle(color: Color(0xFFD9B76E), fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: 2)),
        Text('चार खिलाड़ी • 13 ट्रिक • स्पेड ट्रम्प', style: TextStyle(color: Colors.white)),
      ])),
      const SizedBox(height: 16),
      TextField(controller: _name, maxLength: 18, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'आपका नाम', prefixIcon: Icon(Icons.person))),
      if (_room == null) ...[
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(initialValue: _rounds, decoration: const InputDecoration(labelText: 'मैच में राउंड'), items: [for (var n=5;n<=13;n++) DropdownMenuItem(value:n, child:Text('$n राउंड'))], onChanged: (v) { if(v!=null)setState(()=>_rounds=v); }),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _fillBots, onChanged: (v)=>setState(()=>_fillBots=v), title: const Text('खाली सीटों पर Bots भरें'), subtitle: const Text('1, 2, 3 या 4 असली खिलाड़ियों के साथ शुरू करें')),
        FilledButton.icon(onPressed: _busy ? null : _create, icon: const Icon(Icons.add_circle_outline), label: const Text('Create Room')),
        const Divider(height: 30),
        TextField(controller: _code, maxLength: 6, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Room Code')),
        FilledButton.tonalIcon(onPressed: _busy ? null : _join, icon: const Icon(Icons.login), label: const Text('Join Room')),
      ] else ...[
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('आपका Room तैयार है', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8), SelectableText(_room!.code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 5)),
          Text('खिलाड़ी: ${_room!.players.length}/4', textAlign: TextAlign.center),
          for (final p in _room!.players) ListTile(dense: true, leading: Icon(p.isHost ? Icons.star : Icons.person), title: Text(p.name), subtitle: p.isHost ? const Text('Host') : null),
          if (_room!.hostId == _service.userId) ...[
            FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('Game Start')),
            OutlinedButton.icon(onPressed: _copyInvite, icon: const Icon(Icons.share), label: const Text('Invite Link / Code Copy')),
          ] else const Text('Host के गेम शुरू करने की प्रतीक्षा करें।', textAlign: TextAlign.center),
          SelectableText(_inviteUrl, textAlign: TextAlign.center),
        ]))),
      ],
      if (_busy) const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
      const SizedBox(height: 18),
      const Text('नियम: कुल बोली कम-से-कम 9 • हर खिलाड़ी 13 पत्ते • स्पेड ट्रम्प • हर ट्रिक में रंग फॉलो करना अनिवार्य', style: TextStyle(color: Colors.blueGrey), textAlign: TextAlign.center),
      const Center(child: Padding(padding: EdgeInsets.all(18), child: Text('Developed by Shartendu', style: TextStyle(color: Colors.blueGrey, fontSize: 11)))),
    ]))),
  );
}

class _CallBreakHostTable extends StatefulWidget {
  const _CallBreakHostTable({required this.roomCode, required this.engine, required this.service});
  final String roomCode; final CallBreakEngine engine; final FirebaseRoomService service;
  @override State<_CallBreakHostTable> createState() => _CallBreakHostTableState();
}
class _CallBreakHostTableState extends State<_CallBreakHostTable> {
  StreamSubscription<List<Map<String, dynamic>>>? _actions;
  String? _notice;
  bool _busy = false;
  CallBreakEngine get game => widget.engine;
  @override void initState() { super.initState(); _actions = widget.service.watchActions(widget.roomCode).listen((items) { for (final item in items) { _remoteAction(item); } }, onError: (e)=>_say(e.toString())); _driveBots(); }
  @override void dispose() { unawaited(_actions?.cancel()); super.dispose(); }

  Future<void> _sync() => widget.service.publishGameState(widget.roomCode, game.publicState(), game.privateHands());
  void _remoteAction(Map<String,dynamic> item) {
    if (!mounted || _busy) return;
    final pid = item['playerId']?.toString();
    final action = item['action'];
    if (action is! Map) return;
    final index = game.players.indexWhere((p)=>p.id==pid);
    if(index<0 || game.turn!=index || game.players[index].isBot) return;
    try {
      if(action['type']=='bid') { game.setBid(index, (action['bid'] as num).toInt()); }
      else if(action['type']=='play') { final c=CallBreakEngine.cardFromJson(Map<String,dynamic>.from(action['card'] as Map)); game.play(index,c); }
      _driveBots();
    } catch(e) { _say(e.toString()); unawaited(_sync()); unawaited(_driveBots()); }
  }

  Future<void> _driveBots() async {
    if (_busy) return;
    _busy = true;
    try {
      var guard = 0;
      while (mounted && guard++ < 20) {
        if (game.complete) break;
        final p = game.players[game.turn];
        if (!p.isBot) break;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (game.bidding) {
          try { game.setBid(game.turn, game.estimate(p.hand)); }
          catch (_) { /* low aggregate bid is reset by engine; continue bidding */ }
        } else {
          final legal = game.legalCards(game.turn)..sort((a,b)=>CallBreakEngine.power(a).compareTo(CallBreakEngine.power(b)));
          game.play(game.turn, legal.first);
        }
      }
      await _sync();
      if (mounted) setState(() {});
    } catch(e) { _say(e.toString()); }
    finally { _busy = false; }
  }

  Future<void> _bid(int bid) async {
    try { game.setBid(game.turn, bid); await _driveBots(); } catch(e) { _say(e.toString()); await _sync(); await _driveBots(); }
  }
  Future<void> _play(PlayingCard card) async {
    try { game.play(game.turn, card); await _driveBots(); } catch(e) { _say(e.toString()); }
  }
  Future<void> _next() async { game.nextRound(); await _sync(); if(mounted)setState(()=>_notice=null); await _driveBots(); }
  void _say(String value) { if(mounted)setState(()=>_notice=value.replaceFirst('Bad state: ','')); }

  @override Widget build(BuildContext context) {
    final mine = game.players[game.turn].id == widget.service.userId;
    final me = game.players.indexWhere((p)=>p.id==widget.service.userId);
    return Scaffold(appBar:AppBar(title:Text('CALL BREAK • ${widget.roomCode}'),actions:[IconButton(onPressed:()=>showModalBottomSheet(context:context,builder:(_)=>const _CallBreakRules()),icon:const Icon(Icons.menu_book))]),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[
        _tableHeader(game),
        const SizedBox(height:10),
        for(var i=0;i<4;i++) _playerLine(game.players[i],i==game.turn,i==me),
        const Divider(),
        Text(game.bidding ? (game.players[game.turn].isBot?'Bot बोली लगा रहा है…':'आपकी बोली चुनें') : game.complete ? 'राउंड पूरा' : '${game.players[game.turn].name} की चाल',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),
        if(me>=0) ...[
          const Text('आपके पत्ते',style:TextStyle(fontWeight:FontWeight.w900)),
          Wrap(spacing:6,runSpacing:6,children:[for(final c in game.players[me].hand)ActionChip(label:Text(c.toString(),style:TextStyle(color:c.suit.isRed?Colors.red:Colors.black)),onPressed:!game.bidding && !game.complete && game.turn==me && game.legalCards(me).contains(c)?()=>_play(c):null)]),
        ],
        if(game.bidding && mine) Wrap(spacing:6,children:[for(var n=1;n<=13;n++)ActionChip(label:Text('$n'),onPressed:()=>_bid(n))]),
        if(!game.bidding) Text('टेबल: ${game.trick.map((t)=>'${game.players[t.player].name}: ${t.card}').join('  •  ')}'),
        if(game.complete) Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
          Text(game.matchComplete?'मैच विजेता: ${game.winnerName}':'राउंड स्कोर',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          for(final p in game.players)ListTile(title:Text(p.name),subtitle:Text('बोली ${p.bid} • ट्रिक ${p.tricks}'),trailing:Text(p.score.toStringAsFixed(1))),
          if(!game.matchComplete)FilledButton(onPressed:_next,child:const Text('अगला राउंड')),
        ]))),
        if(_notice!=null)Text(_notice!,style:const TextStyle(color:Colors.red)),
        const SizedBox(height:12),
        VoiceChatPanel(roomCode:widget.roomCode,getFirebaseIdToken:widget.service.getCurrentIdToken),
        const Center(child:Text('Developed by Shartendu',style:TextStyle(color:Colors.blueGrey,fontSize:11))),
      ])));
  }
}

class _CallBreakGuestTable extends StatefulWidget {
  const _CallBreakGuestTable({required this.roomCode,required this.playerId,required this.initial,required this.messages,required this.sendAction,required this.getToken});
  final String roomCode,playerId; final Map<String,dynamic> initial; final Stream<Map<String,dynamic>> messages;
  final Future<void> Function(Map<String,dynamic>) sendAction; final Future<String> Function() getToken;
  @override State<_CallBreakGuestTable> createState()=>_CallBreakGuestTableState();
}
class _CallBreakGuestTableState extends State<_CallBreakGuestTable> {
  late Map<String,dynamic> state; late List<PlayingCard> hand;
  StreamSubscription<Map<String,dynamic>>? sub; String? notice;
  @override void initState(){super.initState();_apply(widget.initial);sub=widget.messages.listen((m){if(m['type']=='game'&&mounted)setState(()=>_apply(m));});}
  void _apply(Map<String,dynamic> m){state=Map<String,dynamic>.from(m['state'] as Map);hand=((m['privateHand'] as List?)??const []).map((v)=>CallBreakEngine.cardFromJson(Map<String,dynamic>.from(v as Map))).toList();}
  @override void dispose(){unawaited(sub?.cancel());super.dispose();}
  List<dynamic> get players=>state['players'] as List<dynamic>;
  int get me=>players.indexWhere((p)=>(p as Map)['id']==widget.playerId);
  int get turn=>(state['turn'] as num).toInt();
  bool get bidding=>state['bidding']==true;
  Future<void> _send(Map<String,dynamic> a)async{try{await widget.sendAction(a);}catch(e){if(mounted)setState(()=>notice=e.toString());}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('CALL BREAK • ${widget.roomCode}')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[
    _guestHeader(state),
    for(var i=0;i<players.length;i++)_guestPlayer(players[i] as Map,i==turn,i==me),
    const Divider(),
    Text(bidding?'बोली का समय':'${(players[turn] as Map)['name']} की चाल',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),
    const Text('आपके पत्ते',style:TextStyle(fontWeight:FontWeight.w900)),
    Wrap(spacing:6,runSpacing:6,children:[for(final c in hand.where((c)=>bidding || state['leadSuit']==null || hand.where((x)=>x.suit.name==state['leadSuit']).isEmpty || c.suit.name==state['leadSuit']))ActionChip(label:Text(c.toString(),style:TextStyle(color:c.suit.isRed?Colors.red:Colors.black)),onPressed:!bidding && turn==me ? ()=>_send({'type':'play','card':CallBreakEngine.cardToJson(c)}) : null)]),
    if(bidding&&turn==me)Wrap(spacing:6,children:[for(var n=1;n<=13;n++)ActionChip(label:Text('$n'),onPressed:()=>_send({'type':'bid','bid':n}))]),
    if(!bidding) Text('टेबल: ${((state['trick'] as List?)??const []).map((t)=>'${(players[(t as Map)['player'] as int] as Map)['name']}: ${CallBreakEngine.cardFromJson(Map<String,dynamic>.from(t['card'] as Map))}').join(' • ')}'),
    if(state['complete']==true)Card(child:Column(children:[const Text('राउंड पूरा'),for(final p in players)ListTile(title:Text(p['name'].toString()),trailing:Text('${p['score']}'))])),
    if(notice!=null)Text(notice!,style:const TextStyle(color:Colors.red)),
    VoiceChatPanel(roomCode:widget.roomCode,getFirebaseIdToken:widget.getToken),
    const Center(child:Text('Developed by Shartendu')),
  ])));
}

Widget _tableHeader(CallBreakEngine g)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF142B45),borderRadius:BorderRadius.circular(16)),child:Column(children:[
  Text('राउंड ${g.round}/${g.roundsToPlay} • ट्रिक ${g.trickNumber+1}/13',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)),
  Text(g.bidding?'कुल बोली ${g.totalBids} (कम-से-कम 9)':'स्पेड ♠ ट्रम्प',style:const TextStyle(color:Color(0xFFD9B76E),fontWeight:FontWeight.w900,fontSize:18)),
]));
Widget _playerLine(CallBreakPlayer p,bool active,bool me)=>Card(color:active?const Color(0xFFE2F4EF):null,child:ListTile(dense:true,leading:Icon(me?Icons.person_pin:Icons.person),title:Text('${p.name}${p.isBot?' • Bot':''}'),subtitle:Text('बोली ${p.bid==0?'—':p.bid} • ट्रिक ${p.tricks}'),trailing:Text(p.score.toStringAsFixed(1),style:const TextStyle(fontWeight:FontWeight.w900))));
Widget _guestHeader(Map<String,dynamic> s)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF142B45),borderRadius:BorderRadius.circular(16)),child:Column(children:[Text('राउंड ${s['round']}/${s['roundsToPlay']} • ट्रिक ${(s['trickNumber'] as num)+1}/13',style:const TextStyle(color:Colors.white)),Text('कुल बोली ${s['totalBids']} • स्पेड ट्रम्प',style:const TextStyle(color:Color(0xFFD9B76E),fontWeight:FontWeight.w900,fontSize:18))]));
Widget _guestPlayer(Map p,bool active,bool me)=>Card(color:active?const Color(0xFFE2F4EF):null,child:ListTile(dense:true,title:Text('${p['name']}${p['isBot']==true?' • Bot':''}'),subtitle:Text('बोली ${p['bid']==0?'—':p['bid']} • ट्रिक ${p['tricks']}'),trailing:Text((p['score'] as num).toStringAsFixed(1))));
class _CallBreakRules extends StatelessWidget { const _CallBreakRules(); @override Widget build(BuildContext context)=>const SafeArea(child:Padding(padding:EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  Text('लकड़ी • CALL BREAK के नियम',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
  Text('चार खिलाड़ी • 52 पत्ते • प्रत्येक को 13 पत्ते। स्पेड (♠) ट्रम्प है। हर खिलाड़ी 1 से 13 तक बोली लगाएगा और सभी बोलियों का योग कम-से-कम 9 होना चाहिए।'),
  SizedBox(height:10),Text('हर चाल में पहले चलाए गए रंग का पत्ता देना अनिवार्य है। रंग न होने पर कोई भी पत्ता या ट्रम्प चल सकते हैं। ट्रम्प में सबसे बड़ा स्पेड, अन्यथा लीड रंग का सबसे बड़ा पत्ता ट्रिक जीतता है।'),
  SizedBox(height:10),Text('बोली पूरी न होने पर बोली के अंक कटेंगे। बोली पूरी होने पर बोली के अंक मिलेंगे और हर अतिरिक्त ट्रिक पर 0.1 अंक जुड़ेंगे। मैच 5 से 13 राउंड का होगा।'),
]))));}
