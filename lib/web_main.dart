// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'network/firebase_room_service.dart';
import 'network/room_models.dart';
import 'network/game_state_codec.dart';
import 'game/scott_game_engine.dart';
import 'screens/game_table_page.dart';
import 'screens/scott_rules_page.dart';
import 'services/scott_audio.dart';

const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

void main() => runApp(const ScottWebApp());

class ScottWebApp extends StatelessWidget {
  const ScottWebApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SCOTT Online',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16A6A1)), scaffoldBackgroundColor: const Color(0xFFF3F6F8)),
    builder: (context, child) => Stack(children: [
      child ?? const SizedBox.shrink(),
      const Positioned(right: 10, bottom: 6, child: IgnorePointer(child: Text('Developed by Shartendu', style: TextStyle(fontSize: 9, color: Color(0x8871808C), fontWeight: FontWeight.w700)))),
    ]),
    home: const ScottWebHome(),
  );
}

class ScottWebHome extends StatefulWidget {
  const ScottWebHome({super.key});
  @override
  State<ScottWebHome> createState() => _ScottWebHomeState();
}

class _ScottWebHomeState extends State<ScottWebHome> {
  final _name = TextEditingController();
  final _code = TextEditingController(text: Uri.base.queryParameters['room'] ?? '');
  final _service = FirebaseRoomService(apiKey: apiKey, databaseUrl: databaseUrl);
  RoomSnapshot? _room;
  bool _busy = false;
  String? _error;
  int _target = 150;
  StreamSubscription<Map<String,dynamic>>? _gameSub;
  Timer? _presenceTimer;
  bool _opened = false;

  @override
  void dispose() { _presenceTimer?.cancel(); _name.dispose(); _code.dispose(); unawaited(_gameSub?.cancel()); unawaited(_service.dispose()); super.dispose(); }

  String get _inviteLink => '${Uri.base.origin}${Uri.base.path}?room=${_room?.code ?? _code.text.trim().toUpperCase()}';

  Future<void> _run(Future<RoomSnapshot> Function() task) async {
    final name = _name.text.trim();
    if (name.isEmpty) { setState(() => _error = 'पहले अपना नाम लिखें।'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final room = await task();
      if (!mounted) return;
      setState(() { _room = room; _busy = false; });
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_service.updatePresence(room.code)));
      unawaited(_service.updatePresence(room.code));
      if (room.hostId != _service.userId) _watchGame(room.code);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Bad state: ', ''); _busy = false; });
    }
  }

  Future<void> _create() => _run(() => _service.createRoom(playerName: _name.text.trim(), targetScore: _target));
  Future<void> _join() => _run(() => _service.joinRoom(code: _code.text.trim().toUpperCase(), playerName: _name.text.trim()));

  void _watchGame(String code) {
    _gameSub?.cancel();
    _gameSub = _service.watchGame(code).listen((m) {
      if (!mounted || _opened || m['type'] != 'game') return;
      _opened = true;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RemoteGameTablePage(
        messages: _service.watchGame(code), sendAction: (a) => unawaited(_service.sendAction(code, a)),
        playerId: _service.userId!, initialMessage: m,
        onLeave: () async {
          final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('गेम छोड़ें?'), content: const Text('आप इस ऑनलाइन गेम से बाहर हो जाएँगे।'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रुकें')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('गेम छोड़ें'))]));
          if (confirmed == true) { await _service.leaveRoom(code); if (mounted) Navigator.of(context).pop(); }
        },
      )));
    }, onError: (e) { if (mounted) setState(() => _error = e.toString()); });
  }

  Future<void> _start() async {
    final room = _room;
    if (room == null || room.hostId != _service.userId || room.players.length < 2) return;
    setState(() { _busy = true; _error = null; });
    try {
      final engine = ScottGameEngine();
      final state = engine.startGame(participants: room.players.map((p) => (id:p.id,name:p.name)).toList(), targetScore: room.targetScore);
      await _service.publishGameState(room.code, GameStateCodec.publicState(state), GameStateCodec.privateHands(state));
      final actions = _service.watchActions(room.code).asyncExpand((items) => Stream<RoomAction>.fromIterable(items.map((i) => (playerId:i['playerId'] as String, action:Map<String,dynamic>.from(i['action'] as Map)))));
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostGameTablePage(engine: engine, initialState: state, hostId: _service.userId!, actions: actions, publish: (s,h) => _service.publishGameState(room.code,s,h), sendToPlayer: (_,__){}, roomPresence: _service.watchRoom(room.code), onLeave: () async { final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('गेम छोड़ें?'), content: const Text('आप डिस्कनेक्ट हो जाएँगे। Host छोड़ता है तो Lobby में Host दूसरे ऑनलाइन खिलाड़ी को दिया जाएगा।'), actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('रुकें')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('गेम छोड़ें'))])); if (confirmed == true) { await _service.leaveRoom(room.code); if (mounted) Navigator.of(context).pop(); } } })));
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: _inviteLink));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite link कॉपी हो गया!')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SCOTT • Online'), actions: [
      IconButton(tooltip: 'खेल के नियम / How to Play', icon: const Icon(Icons.menu_book_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage()))),
      IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottWebSettingsPage()))),
    ]),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: ListView(padding: const EdgeInsets.all(24), children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors:[Color(0xFF142B45),Color(0xFF247A83)]), borderRadius: BorderRadius.circular(24)), child: const Column(children:[Text('SCOTT',style:TextStyle(color:Colors.white,fontSize:36,fontWeight:FontWeight.w900,letterSpacing:4)),Text('Browser से भी खेलें • App जरूरी नहीं',style:TextStyle(color:Colors.white))])),
      const SizedBox(height:14),
      OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage())), icon: const Icon(Icons.menu_book_outlined), label: const Text('खेल के नियम / How to Play')),
      const SizedBox(height:18),
      TextField(controller:_name,maxLength:18,decoration:const InputDecoration(labelText:'आपका नाम',prefixIcon:Icon(Icons.person))),
      if (_room == null) ...[
        DropdownButtonFormField<int>(initialValue:_target,decoration:const InputDecoration(labelText:'Target Score'),items:const [100,150,200].map((v)=>DropdownMenuItem(value:v,child:Text('$v अंक'))).toList(),onChanged:(v){if(v!=null)setState(()=>_target=v);}),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:_busy?null:_create,icon:const Icon(Icons.add),label:const Text('नया Room बनाएँ')),
        const Divider(height:32),
        TextField(controller:_code,maxLength:6,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Room Code')),
        FilledButton.tonalIcon(onPressed:_busy?null:_join,icon:const Icon(Icons.login),label:const Text('Room Join करें')),
      ] else ...[
        Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('Room Code: ${_room!.code}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900),textAlign:TextAlign.center),
          const SizedBox(height:8),Text('Target: ${_room!.targetScore} • खिलाड़ी ${_room!.players.length}/5',textAlign:TextAlign.center),
          const SizedBox(height:8),for(final p in _room!.players) ListTile(leading:Icon(p.isHost?Icons.star:Icons.person),title:Text(p.name),subtitle:p.isHost?const Text('Host'):null),
          if(_room!.hostId==_service.userId)FilledButton.icon(onPressed:_busy||_room!.players.length<2?null:_start,icon:const Icon(Icons.play_arrow),label:const Text('Game Start')),
          OutlinedButton.icon(onPressed:_copyInvite,icon:const Icon(Icons.share),label:const Text('Invite Link Copy करें')),
          SelectableText(_inviteLink,textAlign:TextAlign.center),
        ]))),
        StreamBuilder<RoomSnapshot>(stream:_service.watchRoom(_room!.code),builder:(c,s){if(s.hasData&&s.data!.players.length!=_room!.players.length){WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)setState(()=>_room=s.data);});}return Text('Connected: ${s.data?.players.length ?? _room!.players.length}/5',textAlign:TextAlign.center);}),
      ],
      if(_busy)const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator())),
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:20),const Text('Online game runs through Firebase. 2–5 players per room.',textAlign:TextAlign.center,style:TextStyle(color:Colors.blueGrey)),
      const SizedBox(height:10),
      const Card(child: ListTile(leading: Icon(Icons.wifi_off_outlined), title: Text('Local Wi-Fi Multiplayer'), subtitle: Text('यह सुविधा Android ऐप में उपलब्ध है। Browser सुरक्षा सीमाओं के कारण Web पर Local Wi-Fi Host/Join उपलब्ध नहीं है.'), enabled: false)),
      const SizedBox(height:10),const Center(child: Text('Developed by Shartendu', style: TextStyle(color: Color(0xFF71808C), fontWeight: FontWeight.w800))),
    ]))),
  );
}


class ScottWebSettingsPage extends StatefulWidget {
  const ScottWebSettingsPage({super.key});
  @override
  State<ScottWebSettingsPage> createState() => _ScottWebSettingsPageState();
}

class _ScottWebSettingsPageState extends State<ScottWebSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final audio = ScottAudio.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            SwitchListTile(
              title: const Text('Sound Effects', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('कार्ड, शो, शफल और जीत की आवाज़ें'),
              value: audio.enabled,
              onChanged: (value) => setState(() => audio.enabled = value),
            ),
            const SizedBox(height: 12),
            const Text('Volume', style: TextStyle(fontWeight: FontWeight.w800)),
            Slider(value: audio.volume, min: 0, max: 1, divisions: 10,
              label: '${(audio.volume * 100).round()}%',
              onChanged: (value) => setState(() => audio.volume = value)),
            FilledButton.tonalIcon(onPressed: () => audio.play('tap'),
              icon: const Icon(Icons.volume_up), label: const Text('Test Sound')),
            const Divider(height: 30),
            ListTile(leading: const Icon(Icons.menu_book_outlined),
              title: const Text('खेल के नियम / How to Play'),
              subtitle: const Text('हिंदी और English में पूरी नियमावली'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage()))),
            const ListTile(title: Text('Online Multiplayer'),
              subtitle: Text('Firebase Guest Authentication और Realtime Database')),
            const ListTile(leading: Icon(Icons.wifi_off_outlined), title: Text('Local Wi-Fi'),
              subtitle: Text('केवल Android ऐप में उपलब्ध; Browser में Local Wi-Fi Host/Join समर्थित नहीं है.')),
            const ListTile(title: Text('Developer'), subtitle: Text('Developed by Shartendu')),
          ]),
        ),
      ),
    );
  }
}
