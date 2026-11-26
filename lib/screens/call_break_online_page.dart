import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
// ignore_for_file: deprecated_member_use, prefer_is_empty
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/firebase_room_service.dart';
import '../network/room_models.dart';
import '../game/call_break_engine.dart';
import '../game/playing_card.dart';
import '../services/voice_chat_panel.dart';
import '../services/scott_audio.dart';
import 'about_page.dart';
import '../widgets/call_break_logo.dart';
import 'package:confetti/confetti.dart';

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

  Future<void> _goHome() async {
    final homeUri = Uri.base.replace(queryParameters: const {});
    await launchUrl(homeUri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 68,
      leadingWidth: 76,
      leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'SCOTT Home', onPressed: _goHome, icon: const Icon(Icons.home_rounded), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        const Text('MORE GAMES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .3)),
      ]),
      title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text('लकड़ी • CALL BREAK', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800))),
    ),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF142B45), Color(0xFF247A83)]), borderRadius: BorderRadius.circular(20)), child: const Column(children: [
        SizedBox(height: 4),
        CallBreakLogo(size: 184),
        SizedBox(height: 8),
        Text('लकड़ी • CALL BREAK', textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD9B76E), fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: .6)),
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
      const Text('नियम: कुल बोली कम-से-कम 9 • हर खिलाड़ी 13 पत्ते • स्पेड ट्रम्प • रंग हो तो वही चलाएँ • बड़ा पत्ता हो तो उससे काटें', style: TextStyle(color: Colors.blueGrey), textAlign: TextAlign.center),
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
  late final ConfettiController _confetti = ConfettiController(duration: const Duration(seconds: 3));
  StreamSubscription<List<Map<String, dynamic>>>? _actions;
  String? _notice;
  bool _busy = false;
  CallBreakEngine get game => widget.engine;
  @override void initState() { super.initState(); _actions = widget.service.watchActions(widget.roomCode).listen((items) { for (final item in items) { _remoteAction(item); } }, onError: (e)=>_say(e.toString())); _driveBots(); }
  @override void dispose() { unawaited(_actions?.cancel()); _confetti.dispose(); super.dispose(); }

  Future<void> _sync() => widget.service.publishGameState(widget.roomCode, game.publicState(), game.privateHands());
  void _remoteAction(Map<String,dynamic> item) {
    if (!mounted || _busy) return;
    final pid = item['playerId']?.toString();
    final action = item['action'];
    if (action is! Map) return;
    final index = game.players.indexWhere((p)=>p.id==pid);
    if(index<0 || game.turn!=index || game.players[index].isBot) return;
    try {
      var trickCompleted = false;
      if(action['type']=='bid') {
        game.setBid(index, (action['bid'] as num).toInt());
        unawaited(ScottAudio.instance.play('tap'));
      } else if(action['type']=='play') {
        final c=CallBreakEngine.cardFromJson(Map<String,dynamic>.from(action['card'] as Map));
        final previousTrick = game.trickNumber;
        game.play(index,c);
        trickCompleted = game.trickNumber > previousTrick;
        unawaited(ScottAudio.instance.play('card_discard'));
        if(trickCompleted) { unawaited(ScottAudio.instance.play('winner')); _confetti.play(); }
      }
      if (mounted) setState(() {});
      unawaited(() async {
        await _sync();
        if (trickCompleted) await Future<void>.delayed(const Duration(milliseconds: 1250));
        await _driveBots();
      }());
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
        await Future<void>.delayed(const Duration(milliseconds: 720));
        var trickCompleted = false;
        if (game.bidding) {
          try {
            game.setBid(game.turn, game.estimate(p.hand));
            unawaited(ScottAudio.instance.play('tap'));
          } catch (_) {
            // A low aggregate bid resets the bidding; publish that reset as a new step.
          }
        } else {
          final legal = game.legalCards(game.turn)..sort((a,b)=>CallBreakEngine.power(a).compareTo(CallBreakEngine.power(b)));
          final previousTrick = game.trickNumber;
          game.play(game.turn, legal.first);
          trickCompleted = game.trickNumber > previousTrick;
          unawaited(ScottAudio.instance.play('card_discard'));
          if (trickCompleted) {
            unawaited(ScottAudio.instance.play('winner'));
            _confetti.play();
          }
        }
        // Publish every individual action so all browsers see the same turn sequence.
        if (mounted) setState(() {});
        await _sync();
        if (trickCompleted) {
          await Future<void>.delayed(const Duration(milliseconds: 1350));
        }
      }
    } catch(e) { _say(e.toString()); }
    finally { _busy = false; }
  }

  Future<void> _bid(int bid) async {
    try { game.setBid(game.turn, bid); unawaited(ScottAudio.instance.play('tap')); await _driveBots(); } catch(e) { _say(e.toString()); await _sync(); await _driveBots(); }
  }
  Future<void> _play(PlayingCard card) async {
    try {
      final previousTrick = game.trickNumber;
      game.play(game.turn, card);
      final trickCompleted = game.trickNumber > previousTrick;
      unawaited(ScottAudio.instance.play('card_discard'));
      if (trickCompleted) { unawaited(ScottAudio.instance.play('winner')); _confetti.play(); }
      if (mounted) setState(() {});
      await _sync();
      if (trickCompleted) await Future<void>.delayed(const Duration(milliseconds: 1350));
      await _driveBots();
    } catch(e) { _say(e.toString()); }
  }
  Future<void> _next() async { unawaited(ScottAudio.instance.play('shuffle')); game.nextRound(); await _sync(); if(mounted)setState(()=>_notice=null); await _driveBots(); }
  void _say(String value) { if(mounted)setState(()=>_notice=value.replaceFirst('Bad state: ','')); }

  @override Widget build(BuildContext context) {
    final mine = game.players[game.turn].id == widget.service.userId;
    final me = game.players.indexWhere((p)=>p.id==widget.service.userId);
    return Scaffold(appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[const Text('लकड़ी • CALL BREAK',maxLines:1,style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('Room ${widget.roomCode}',style:const TextStyle(fontSize:10))]),actions:[IconButton(tooltip:'About SCOTT',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AboutPage())),icon:const Icon(Icons.info_outline)),IconButton(tooltip:'नियम',onPressed:()=>showModalBottomSheet(context:context,builder:(_)=>const _CallBreakRules()),icon:const Icon(Icons.menu_book))]),
      body:Stack(children:[SafeArea(child:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF102D27),Color(0xFF071D19)])),child:ListView(padding:const EdgeInsets.all(12),children:[
        _tableHeader(game),
        const SizedBox(height:10),
        _callBreakTable(
          players: [for (final p in game.players) {'name':p.name,'isBot':p.isBot,'bid':p.bid,'tricks':p.tricks,'score':p.score}],
          trick: [for (final t in (game.trick.isNotEmpty?game.trick:game.lastTrick)) {'player':t.player,'card':t.card.toString()}],
          turn: game.turn, me: me,
          winner: game.trick.isEmpty ? game.lastTrickWinner : null,
        ),
        if(me>=0) ...[
          const Text('आपके पत्ते',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:14)),
          Wrap(spacing:5,runSpacing:5,children:[for(final c in game.players[me].hand)ActionChip(
            visualDensity:VisualDensity.compact, materialTapTargetSize:MaterialTapTargetSize.shrinkWrap,
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:2), labelPadding:EdgeInsets.zero,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
            label:Text(c.toString(),style:TextStyle(color:c.suit.isRed?Colors.red:Colors.black,fontSize:14,fontWeight:FontWeight.w600)),
            onPressed:!game.bidding && !game.complete && game.turn==me && game.legalCards(me).contains(c)?()=>_play(c):null)]),
        ],
        if(game.bidding && mine) Wrap(spacing:6,children:[for(var n=1;n<=13;n++)ActionChip(label:Text('$n'),onPressed:()=>_bid(n))]),
        const Divider(color:Color(0x55FFFFFF)),
        _turnBanner(
          title: game.bidding
              ? (game.players[game.turn].isBot ? 'Bot बोली लगा रहा है' : 'आपकी बोली')
              : game.complete ? 'राउंड पूरा' : '${game.players[game.turn].name} की चाल',
          subtitle: game.bidding ? 'बोली का क्रम चल रहा है' : 'अब इसी खिलाड़ी की बारी है',
          isMine: mine && !game.bidding && !game.complete,
        ),
        _previousTrickPanel([for (final p in game.players) {'name':p.name}], [for (final t in game.lastTrick) {'player':t.player,'card':t.card.toString()}]),
        
        if(game.complete) Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
          Text(game.matchComplete?'मैच विजेता: ${game.winnerName}':'राउंड स्कोर',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          for(final p in game.players)ListTile(title:Text(p.name),subtitle:Text('बोली ${p.bid} • ट्रिक ${p.tricks}'),trailing:Text(p.score.toStringAsFixed(1))),
          if(!game.matchComplete)FilledButton(onPressed:_next,child:const Text('अगला राउंड')),
        ]))),
        if(_notice!=null)Text(_notice!,style:const TextStyle(color:Colors.red)),
        const SizedBox(height:12),
        VoiceChatPanel(roomCode:widget.roomCode,getFirebaseIdToken:widget.service.getCurrentIdToken),
        const Center(child:Text('Developed by Shartendu',style:TextStyle(color:Colors.white70,fontSize:11))),
        _scorecardButton(context,
          players: [for (final p in game.players) {'id':p.id,'name':p.name,'bid':p.bid,'tricks':p.tricks,'score':p.score}],
          history: game.roundHistory, currentRound: game.round, roundComplete: game.complete),
      ]))),Positioned.fill(child:IgnorePointer(child:ConfettiWidget(confettiController:_confetti,blastDirectionality:BlastDirectionality.explosive,shouldLoop:false,numberOfParticles:35,gravity:0.18,colors:const [Color(0xFFFFD56A),Colors.white,Color(0xFF16A6A1)]))) ]));
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
  List<PlayingCard> get legalHandCards {
    final suitName = state['leadSuit'] as String?;
    final currentTrick = ((state['trick'] as List?) ?? const []).map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return (player: (item['player'] as num).toInt(),
        card: CallBreakEngine.cardFromJson(Map<String, dynamic>.from(item['card'] as Map)));
    }).toList();
    return CallBreakEngine.legalCardsForHand(hand,
      leadSuit: suitName == null ? null : CardSuit.values.byName(suitName),
      trick: currentTrick);
  }
  Future<void> _send(Map<String,dynamic> a)async{try{await widget.sendAction(a);}catch(e){if(mounted)setState(()=>notice=e.toString());}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[const Text('लकड़ी • CALL BREAK',maxLines:1,style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('Room ${widget.roomCode}',style:const TextStyle(fontSize:10))]),actions:[IconButton(tooltip:'About SCOTT',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AboutPage())),icon:const Icon(Icons.info_outline)),IconButton(tooltip:'नियम',onPressed:()=>showModalBottomSheet(context:context,builder:(_)=>const _CallBreakRules()),icon:const Icon(Icons.menu_book))]),body:SafeArea(child:ListView(padding:const EdgeInsets.all(12),children:[
    _guestHeader(state),
    _callBreakTable(
      players: [for (final p in players) Map<String,dynamic>.from(p as Map)],
      trick: [for (final t in ((state['trick'] as List?)?.isNotEmpty == true ? state['trick'] as List : (state['lastTrick'] as List? ?? const []))) {
        'player':(t as Map)['player'],
        'card':CallBreakEngine.cardFromJson(Map<String,dynamic>.from(t['card'] as Map)).toString(),
      }],
      turn: turn, me: me,
      winner: (state['trick'] as List? ?? const []).isEmpty ? state['lastTrickWinner'] as int? : null,
    ),
    const Text('आपके पत्ते',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:14)),
    Wrap(spacing:5,runSpacing:5,children:[for(final c in hand.where((c)=>bidding || legalHandCards.contains(c)))ActionChip(
      visualDensity:VisualDensity.compact, materialTapTargetSize:MaterialTapTargetSize.shrinkWrap,
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:2), labelPadding:EdgeInsets.zero,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
      label:Text(c.toString(),style:TextStyle(color:c.suit.isRed?Colors.red:Colors.black,fontSize:14,fontWeight:FontWeight.w600)),
      onPressed:!bidding && turn==me ? ()=>_send({'type':'play','card':CallBreakEngine.cardToJson(c)}) : null)]),
    if(bidding&&turn==me)Wrap(spacing:6,children:[for(var n=1;n<=13;n++)ActionChip(label:Text('$n'),onPressed:()=>_send({'type':'bid','bid':n}))]),
    _turnBanner(
      title: bidding ? '${(players[turn] as Map)['name']} की बोली' : '${(players[turn] as Map)['name']} की चाल',
      subtitle: bidding ? 'बोली का क्रम चल रहा है' : 'अब इसी खिलाड़ी की बारी है',
      isMine: !bidding && turn == me,
    ),
    _previousTrickPanel([for (final p in players) Map<String,dynamic>.from(p as Map)], [for (final t in (state['lastTrick'] as List? ?? const [])) {'player':(t as Map)['player'],'card':CallBreakEngine.cardFromJson(Map<String,dynamic>.from(t['card'] as Map)).toString()}]),

    if(state['complete']==true)Card(child:Column(children:[const Text('राउंड पूरा'),for(final p in players)ListTile(title:Text(p['name'].toString()),trailing:Text('${p['score']}'))])),
    if(notice!=null)Text(notice!,style:const TextStyle(color:Colors.red)),
    VoiceChatPanel(roomCode:widget.roomCode,getFirebaseIdToken:widget.getToken),
    const Center(child:Text('Developed by Shartendu')),
    _scorecardButton(context,
      players: [for (final p in players) Map<String,dynamic>.from(p as Map)],
      history: (state['roundHistory'] as List? ?? const []),
      currentRound: (state['round'] as num).toInt(),
      roundComplete: state['complete'] == true),
  ])));
}



Widget _scorecardButton(BuildContext context, {
  required List<dynamic> players,
  required List<dynamic> history,
  required int currentRound,
  required bool roundComplete,
}) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 8),
  child: OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFFFD56A),
      side: const BorderSide(color: Color(0x99FFD56A)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      backgroundColor: const Color(0xFF12372D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    onPressed: () => _showScorecard(context, players: players, history: history,
      currentRound: currentRound, roundComplete: roundComplete),
    icon: const Icon(Icons.leaderboard_rounded),
    label: const Text('स्कोरकार्ड', style: TextStyle(fontWeight: FontWeight.w900)),
  ),
);

void _showScorecard(BuildContext context, {
  required List<dynamic> players,
  required List<dynamic> history,
  required int currentRound,
  required bool roundComplete,
}) {
  final rounds = <Map<String, dynamic>>[
    for (final item in history) Map<String, dynamic>.from(item as Map),
  ];
  if (!roundComplete) {
    rounds.add({
      'round': currentRound,
      'inProgress': true,
      'players': [for (final p in players) {
        'id': p['id'], 'name': p['name'], 'bid': p['bid'] ?? 0,
        'tricks': p['tricks'] ?? 0, 'roundScore': null,
        'totalScore': p['score'] ?? 0,
      }],
    });
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B211B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .78,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Row(children: [
              const Icon(Icons.leaderboard_rounded, color: Color(0xFFFFD56A)),
              const SizedBox(width: 9),
              const Expanded(child: Text('गेम स्कोरकार्ड',
                style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900))),
              IconButton(onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close, color: Colors.white70)),
            ]),
          ),
          const Divider(color: Color(0x447CC6A3), height: 1),
          Expanded(child: rounds.isEmpty
            ? const Center(child: Text('पहला राउंड पूरा होने पर स्कोर यहाँ दिखेगा।',
                style: TextStyle(color: Colors.white70)))
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final roundData in rounds) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xE6133028),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x667CC6A3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('राउंड ${roundData['round']}${roundData['inProgress'] == true ? ' • जारी है' : ''}',
                        style: const TextStyle(color: Color(0xFFFFD56A), fontSize: 15, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Row(children: [
                        Expanded(flex: 4, child: Text('खिलाड़ी', style: TextStyle(color: Colors.white54, fontSize: 10))),
                        Expanded(flex: 5, child: Text('बोली • ट्रिक', style: TextStyle(color: Colors.white54, fontSize: 10))),
                        Expanded(flex: 2, child: Text('राउंड', textAlign: TextAlign.end, style: TextStyle(color: Colors.white54, fontSize: 10))),
                        Expanded(flex: 2, child: Text('कुल', textAlign: TextAlign.end, style: TextStyle(color: Colors.white54, fontSize: 10))),
                      ]),
                      const Divider(color: Color(0x337CC6A3), height: 10),
                      for (final raw in (roundData['players'] as List? ?? const []))
                        Builder(builder: (_) {
                          final p = Map<String, dynamic>.from(raw as Map);
                          final score = p['roundScore'];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Expanded(flex: 4, child: Text('${p['name']}',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                              Expanded(flex: 5, child: Text(
                                'बोली ${p['bid']}  •  ट्रिक ${p['tricks']}',
                                style: const TextStyle(color: Color(0xFFD5E7DE), fontSize: 11))),
                              Expanded(flex: 2, child: Text(
                                score == null ? '—' : (score as num).toStringAsFixed(1),
                                textAlign: TextAlign.end,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                              Expanded(flex: 2, child: Text(
                                (p['totalScore'] as num? ?? 0).toStringAsFixed(1),
                                textAlign: TextAlign.end,
                                style: const TextStyle(color: Color(0xFFFFD56A), fontWeight: FontWeight.w900))),
                            ]),
                          );
                        }),
                      const Divider(color: Color(0x337CC6A3), height: 10),

                    ]),
                  ),
                ],
              ])),
        ]),
      ),
    ),
  );
}

class _CallBreakTable extends StatefulWidget {
  const _CallBreakTable({required this.players, required this.trick, required this.turn, required this.me, this.winner});
  final List<Map<String,dynamic>> players, trick;
  final int turn, me; final int? winner;
  @override State<_CallBreakTable> createState() => _CallBreakTableState();
}
class _CallBreakTableState extends State<_CallBreakTable> {
  Timer? _timer; bool _collecting = false; String _key = '';
  String get _signature => '${widget.trick.map((p) => '${p['player']}:${p['card']}').join('|')}:${widget.winner}';
  @override void initState() { super.initState(); _schedule(); }
  @override void didUpdateWidget(covariant _CallBreakTable oldWidget) { super.didUpdateWidget(oldWidget); if (_signature != _key) _schedule(); }
  void _schedule() {
    _timer?.cancel(); _key = _signature; _collecting = false;
    if (widget.winner != null && widget.trick.length == 4) {
      _timer = Timer(const Duration(milliseconds: 950), () { if (mounted) setState(() => _collecting = true); });
    }
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final players = widget.players, trick = widget.trick; final winner = widget.winner;
    final self = widget.me >= 0 && widget.me < players.length ? widget.me : 0;
    final top = (self + 2) % 4, left = (self + 3) % 4, right = (self + 1) % 4;
    Widget seat(int index) {
      final p = players[index], active = index == widget.turn, isMe = index == self;
      return AnimatedContainer(duration: const Duration(milliseconds: 260), width: 116, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(color: active ? const Color(0xFF285E48) : const Color(0xCC09251F), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? const Color(0xFFFFD56A) : const Color(0x557CC6A3), width: active ? 2 : 1),
          boxShadow: [if(active) const BoxShadow(color: Color(0x88FFD56A), blurRadius: 13, spreadRadius: 1)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(isMe ? Icons.person_pin_circle : Icons.person, size: 15, color: active ? const Color(0xFFFFD56A) : Colors.white70), const SizedBox(width: 4),
            Flexible(child: Text('${p['name'] ?? 'Player'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 3), Text('बोली ${p['bid'] == null || p['bid'] == 0 ? '—' : p['bid']}  •  ट्रिक ${p['tricks'] ?? 0}', style: const TextStyle(color: Color(0xFFD5E7DE), fontSize: 9, fontWeight: FontWeight.w600)),
          Text('${p['isBot'] == true ? 'BOT  •  ' : ''}स्कोर ${(p['score'] as num? ?? 0).toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFFFFD56A), fontSize: 9, fontWeight: FontWeight.w800)),
        ]));
    }
    Widget card(Map<String,dynamic> play) { final value = play['card']?.toString() ?? ''; final red = value.contains('♥') || value.contains('♦');
      return Container(key: ValueKey('${play['player']}-$value'), width: 48, height: 68, padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFE8E4D9)]), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD5CBB5)), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 9, offset: Offset(2, 4))]),
        child: Center(child: Text(value, textAlign: TextAlign.center, style: TextStyle(color: red ? const Color(0xFFB51F32) : const Color(0xFF18251F), fontSize: 19, fontWeight: FontWeight.w900))));
    }
    final moving = _collecting && winner != null && trick.length == 4;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 366, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(30),
        gradient: const RadialGradient(center: Alignment(0, -.12), radius: 1.25, colors: [Color(0xFF286B4D), Color(0xFF124331), Color(0xFF08271F)]), border: Border.all(color: const Color(0xFFD2B36B), width: 3), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))]),
        child: LayoutBuilder(builder: (context, bounds) {
          final w = bounds.maxWidth; final positions = <int,Offset>{0:Offset(w/2-24,224),1:Offset(w-76,150),2:Offset(w/2-24,94),3:const Offset(8,150)};
          final rel = winner == null ? -1 : (winner-self+4)%4;
          final target = rel==0 ? Offset(w/2-24,300) : rel==1 ? Offset(w-74,142) : rel==2 ? Offset(w/2-24,8) : const Offset(4,142);
          return Stack(clipBehavior: Clip.hardEdge, children: [
            const Positioned(top:83,left:0,right:0,child:Center(child:Text('SCOTT  •  CALL BREAK',style:TextStyle(color:Color(0x77FFFFFF),letterSpacing:3,fontSize:10,fontWeight:FontWeight.w900)))),
            Positioned(top:8,left:w/2-58,child:seat(top)), Positioned(left:5,top:144,child:seat(left)), Positioned(right:5,top:144,child:seat(right)), Positioned(bottom:7,left:w/2-58,child:seat(self)),
            for (final play in trick) Builder(builder: (_) { final player=(play['player'] as num).toInt(); final relative=(player-self+4)%4; final pos=moving?target:positions[relative]!;
              return AnimatedPositioned(key:ValueKey('play-$player-${play['card']}'),duration:Duration(milliseconds:moving?1050:420),curve:moving?Curves.easeInOutCubic:Curves.easeOutBack,left:pos.dx,top:pos.dy,
                child:AnimatedOpacity(duration:const Duration(milliseconds:1050),opacity:moving?0:1,child:Transform.scale(scale: moving ? .62 : 1,child:card(play)))); }),
            if (winner != null && trick.length == 4) Positioned(top:184,left:0,right:0,child:Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:9),
              decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFFE08A),Color(0xFFD4A83F)]),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white,width:1.5),boxShadow:const [BoxShadow(color:Colors.black45,blurRadius:12,offset:Offset(0,4))]),
              child:Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.emoji_events,color:Color(0xFF38280A),size:18),const SizedBox(width:6),Text('${players[winner]['name']}  •  इस ट्रिक का विजेता',style:const TextStyle(color:Color(0xFF38280A),fontSize:12,fontWeight:FontWeight.w900))])))),
            if (trick.isEmpty) const Positioned(left:0,right:0,top:174,child:Center(child:Text('कार्ड की चाल यहाँ आएगी',style:TextStyle(color:Color(0x88FFFFFF),fontSize:10)))),
          ]);
        })),
    ]);
  }
}
Widget _previousTrickPanel(List<Map<String,dynamic>> players, List<Map<String,dynamic>> trick) => Container(width:double.infinity,margin:const EdgeInsets.only(top:2,bottom:5),padding:const EdgeInsets.symmetric(horizontal:9,vertical:8),
  decoration:BoxDecoration(color:const Color(0xE6091714),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0x667CC6A3))),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('पिछली चाल के पत्ते',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w900)),const SizedBox(height:6),
    if(trick.isEmpty) const Text('पहली चाल पूरी होने पर यहाँ पत्ते दिखेंगे',style:TextStyle(color:Color(0xFFCFDDD6),fontSize:10))
    else Wrap(spacing:6,runSpacing:5,children:[for(final play in trick) Builder(builder:(_){
      final index=(play['player'] as num).toInt(), value=play['card']?.toString()??'', red=value.contains('♥')||value.contains('♦');
      final name=index>=0&&index<players.length?players[index]['name']?.toString()??'Player':'Player';
      return Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:5),decoration:BoxDecoration(color:const Color(0xFF203B32),borderRadius:BorderRadius.circular(9),border:Border.all(color:const Color(0x557CC6A3))),
        child:Row(mainAxisSize:MainAxisSize.min,children:[Text(name,style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800)),const SizedBox(width:5),
          Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),decoration:BoxDecoration(color:const Color(0xFFF4F0E6),borderRadius:BorderRadius.circular(5)),child:Text(value,style:TextStyle(color:red?const Color(0xFFB51F32):const Color(0xFF18251F),fontSize:11,fontWeight:FontWeight.w900))) ]));
    })]),
  ]));
Widget _callBreakTable({required List<Map<String,dynamic>> players,required List<Map<String,dynamic>> trick,required int turn,required int me,int? winner}) =>
  _CallBreakTable(players:players,trick:trick,turn:turn,me:me,winner:winner);

Widget _turnBanner({required String title, required String subtitle, required bool isMine}) => Container(
  margin: const EdgeInsets.symmetric(vertical: 10),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: isMine
      ? const [Color(0xFF236B50), Color(0xFF164A3A)]
      : const [Color(0xFF173B36), Color(0xFF102B28)]),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: isMine ? const Color(0xFFFFD56A) : const Color(0x6688B9A5), width: isMine ? 2 : 1),
    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 9, offset: Offset(0,4))],
  ),
  child: Row(children: [
    Icon(isMine ? Icons.touch_app : Icons.hourglass_top_rounded, color: const Color(0xFFFFD56A), size: 25),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
      Text(subtitle, style: const TextStyle(color: Color(0xFFD7E9E0), fontSize: 12, fontWeight: FontWeight.w600)),
    ])),
    if (isMine) const Text('आपकी बारी', style: TextStyle(color: Color(0xFFFFD56A), fontWeight: FontWeight.w900, fontSize: 11)),
  ]),
);

Widget _tableHeader(CallBreakEngine g)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF142B45),borderRadius:BorderRadius.circular(16)),child:Column(children:[
  Text('राउंड ${g.round}/${g.roundsToPlay} • ट्रिक ${g.trickNumber+1}/13',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)),
  Text(g.bidding?'कुल बोली ${g.totalBids} (कम-से-कम 9)':'स्पेड ♠ ट्रम्प',style:const TextStyle(color:Color(0xFFD9B76E),fontWeight:FontWeight.w900,fontSize:18)),
]));
Widget _guestHeader(Map<String,dynamic> s)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF142B45),borderRadius:BorderRadius.circular(16)),child:Column(children:[Text('राउंड ${s['round']}/${s['roundsToPlay']} • ट्रिक ${(s['trickNumber'] as num)+1}/13',style:const TextStyle(color:Colors.white)),Text('कुल बोली ${s['totalBids']} • स्पेड ट्रम्प',style:const TextStyle(color:Color(0xFFD9B76E),fontWeight:FontWeight.w900,fontSize:18))]));
class _CallBreakRules extends StatelessWidget { const _CallBreakRules(); @override Widget build(BuildContext context)=>const SafeArea(child:Padding(padding:EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  Text('लकड़ी • CALL BREAK के नियम',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
  Text('चार खिलाड़ी • 52 पत्ते • प्रत्येक को 13 पत्ते। स्पेड (♠) ट्रम्प है। हर खिलाड़ी 1 से 13 तक बोली लगाएगा और सभी बोलियों का योग कम-से-कम 9 होना चाहिए।'),
  SizedBox(height:10),Text('जिस रंग से चाल शुरू हुई है, वह रंग आपके पास हो तो वही चलाना अनिवार्य है। उस रंग में यदि टेबल पर पड़े सबसे बड़े पत्ते से बड़ा पत्ता आपके पास है, तो उससे बड़ा पत्ता चलाना जरूरी है; इनमें से कोई भी बड़ा पत्ता चुन सकते हैं, सबसे बड़ा ही चलाना जरूरी नहीं। बड़ा पत्ता न हो तो उसी रंग का कोई भी पत्ता चल सकता है। रंग न होने पर स्पेड से काटना वैकल्पिक है—आप कोई दूसरा पत्ता भी चला सकते हैं। स्पेड ट्रम्प है।'),
  SizedBox(height:10),Text('बोली पूरी न होने पर बोली के अंक कटेंगे। बोली पूरी होने पर बोली के अंक मिलेंगे और हर अतिरिक्त ट्रिक पर 0.1 अंक जुड़ेंगे। मैच 5 से 13 राउंड का होगा।'),
]))));}
