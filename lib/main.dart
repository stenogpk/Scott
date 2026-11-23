// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network/firebase_room_service.dart';
import 'network/local_room_client.dart';
import 'network/local_room_server.dart';
import 'network/room_models.dart';
import 'game/scott_game_engine.dart';
import 'screens/game_table_page.dart';
import 'screens/scott_rules_page.dart';
import 'network/game_state_codec.dart';
import 'services/scott_audio.dart';

const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const firebaseDatabaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');

void main() => runApp(const ScottApp());

class ScottApp extends StatelessWidget {
  const ScottApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SCOTT',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16A6A1), primary: const Color(0xFF142B45)),
      scaffoldBackgroundColor: const Color(0xFFF3F6F8),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF142B45), foregroundColor: Colors.white, centerTitle: true),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    ),
    builder: (context, child) => Stack(children: [
      child ?? const SizedBox.shrink(),
      const Positioned(right: 10, bottom: 6, child: IgnorePointer(child: Text('Developed by Shartendu', style: TextStyle(fontSize: 9, color: Color(0x8871808C), fontWeight: FontWeight.w700)))),
    ]),
    home: const ProfileGate(),
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  Future<Map<String, String?>>? _profile;
  @override
  void initState() { super.initState(); _profile = _load(); }
  Future<Map<String, String?>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    return {'name': prefs.getString('scott_profile_name'), 'gender': prefs.getString('scott_profile_gender')};
  }
  Future<void> _delete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('scott_profile_name');
    await prefs.remove('scott_profile_gender');
    if (mounted) setState(() => _profile = _load());
  }
  Future<void> _save(String name, String gender) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scott_profile_name', name.trim());
    await prefs.setString('scott_profile_gender', gender);
    if (mounted) setState(() => _profile = _load());
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String?>>(
    future: _profile,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final name = snapshot.data!['name'];
      final gender = snapshot.data!['gender'];
      if (name == null || name.trim().isEmpty || gender == null) {
        return ProfileEditorPage(onSaved: _save, onDeleted: _delete, firstRun: true);
      }
      return ScottHomePage(profileName: name, profileGender: gender, onProfileChanged: _save, onProfileDeleted: _delete);
    },
  );
}

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({super.key, required this.onSaved, required this.onDeleted, this.firstRun = false, this.initialName = '', this.initialGender = 'अन्य'});
  final Future<void> Function(String name, String gender) onSaved;
  final Future<void> Function() onDeleted;
  final bool firstRun;
  final String initialName;
  final String initialGender;
  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  late String _gender = widget.initialGender;
  bool _saving = false;
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('अपना नाम लिखें।'))); return; }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await widget.onSaved(name, _gender);
    if (!mounted) return;
    if (!widget.firstRun) navigator.pop();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.firstRun ? 'अपना प्रोफाइल बनाएँ' : 'प्रोफाइल एडिट करें'), automaticallyImplyLeading: !widget.firstRun),
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.account_circle_rounded, size: 84, color: Color(0xFF168B87)),
      const SizedBox(height: 12),
      Text(widget.firstRun ? 'SCOTT में आपका स्वागत है' : 'अपनी जानकारी अपडेट करें', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 24),
      TextField(controller: _name, maxLength: 18, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'आपका नाम', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: _gender, decoration: const InputDecoration(labelText: 'Gender'), items: const [DropdownMenuItem(value: 'पुरुष', child: Text('पुरुष')), DropdownMenuItem(value: 'महिला', child: Text('महिला')), DropdownMenuItem(value: 'अन्य', child: Text('अन्य / बताना नहीं चाहते'))], onChanged: (v) { if (v != null) setState(() => _gender = v); }),
      const SizedBox(height: 22),
      if (widget.firstRun) TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage())), icon: const Icon(Icons.menu_book_outlined), label: const Text('खेल के नियम / How to Play')),
      FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check_circle_outline), label: Text(_saving ? 'सेव हो रहा है…' : 'प्रोफाइल सेव करें')),
      if (!widget.firstRun) ...[
        const SizedBox(height: 18),
        OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), onPressed: _saving ? null : () async {
          final navigator = Navigator.of(context);
          final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('प्रोफाइल डिलीट करें?'), content: const Text('आपका सेव किया हुआ नाम और Gender इस फोन से हट जाएगा। अगली बार ऐप खोलने पर नया प्रोफाइल बनाना होगा।'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द करें')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('हाँ, डिलीट करें'))]));
          if (confirmed == true) {
            await widget.onDeleted();
            if (!mounted) return;
            if (!widget.firstRun) navigator.pop();
          }
        }, icon: const Icon(Icons.delete_outline), label: const Text('प्रोफाइल डिलीट करें')),
      ],
    ]))))),
  );
}

class ScottHomePage extends StatefulWidget {
  const ScottHomePage({super.key, required this.profileName, required this.profileGender, required this.onProfileChanged, required this.onProfileDeleted});
  final String profileName;
  final String profileGender;
  final Future<void> Function(String name, String gender) onProfileChanged;
  final Future<void> Function() onProfileDeleted;
  @override
  State<ScottHomePage> createState() => _ScottHomePageState();
}

class _ScottHomePageState extends State<ScottHomePage> {
  late final TextEditingController _name = TextEditingController(text: widget.profileName);
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SCOTT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)), actions: [IconButton(tooltip: 'Edit Profile', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditorPage(onSaved: widget.onProfileChanged, onDeleted: widget.onProfileDeleted, initialName: widget.profileName, initialGender: widget.profileGender))), icon: const Icon(Icons.edit_outlined)), IconButton(tooltip: 'Settings', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottSettingsPage())), icon: const Icon(Icons.settings_outlined))]),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF142B45), Color(0xFF247A83)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Column(children: [
              Icon(Icons.style_rounded, color: Colors.white, size: 68),
              SizedBox(height: 12),
              Text('SCOTT', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
              SizedBox(height: 8),
              Text('हर चाल में दिमाग, हर राउंड में मज़ा!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
              SizedBox(height: 6),
              Text('2 से 5 खिलाड़ियों का कार्ड गेम', style: TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 22),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Row(children: [const CircleAvatar(child: Icon(Icons.person)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.profileName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text(widget.profileGender, style: const TextStyle(color: Colors.blueGrey))])), IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditorPage(onSaved: widget.onProfileChanged, onDeleted: widget.onProfileDeleted, initialName: widget.profileName, initialGender: widget.profileGender))), icon: const Icon(Icons.edit_outlined))])),
          const SizedBox(height: 12),
          _HomeModeCard(icon: Icons.public, title: 'Online Multiplayer', subtitle: 'दूर बैठे दोस्तों के साथ Room Code से खेलें', onTap: () => _open(context, OnlineRoomPage(playerName: _playerName))),
          const SizedBox(height: 12),
          _HomeModeCard(icon: Icons.wifi, title: 'Local Wi-Fi Multiplayer', subtitle: 'एक ही Wi-Fi / Hotspot पर, इंटरनेट के बिना', onTap: () => _open(context, LocalWifiPage(playerName: _playerName))),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage())), icon: const Icon(Icons.menu_book_outlined), label: const Text('खेल के नियम / How to Play')),
          const SizedBox(height: 18),
          const Text('खेल में 2–5 खिलाड़ी • 52 पत्ते • नौकी (9) शून्य अंक', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF607080))),
          const SizedBox(height: 14),
          const Text('Developed by Shartendu', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7B89), fontWeight: FontWeight.w700)),
        ],
      )),
    ))),
  );

  String get _playerName => widget.profileName;
  void _open(BuildContext context, Widget page) {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पहले अपना खिलाड़ी नाम लिखें।')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class ScottSettingsPage extends StatefulWidget {
  const ScottSettingsPage({super.key});
  @override
  State<ScottSettingsPage> createState() => _ScottSettingsPageState();
}
class _ScottSettingsPageState extends State<ScottSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final audio = ScottAudio.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SwitchListTile(
          title: const Text('Sound Effects', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('कार्ड, शो, शफल और जीत की आवाज़ें'),
          value: audio.enabled,
          onChanged: (value) => setState(() => audio.enabled = value),
        ),
        const SizedBox(height: 12),
        const Text('Volume', style: TextStyle(fontWeight: FontWeight.w800)),
        Slider(value: audio.volume, min: 0, max: 1, divisions: 10, label: '${(audio.volume * 100).round()}%', onChanged: (value) => setState(() => audio.volume = value)),
        FilledButton.tonalIcon(onPressed: () => audio.play('tap'), icon: const Icon(Icons.volume_up), label: const Text('Test Sound')),
        ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('खेल के नियम / How to Play'), subtitle: const Text('हिंदी और English में पूरी नियमावली'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage()))),
        const Divider(height: 30),
        const ListTile(title: Text('Online Multiplayer'), subtitle: Text('Firebase Guest Authentication और Realtime Database')),
        const ListTile(title: Text('Local Wi-Fi'), subtitle: Text('एक ही Wi-Fi / Hotspot पर बिना इंटरनेट')),
        const ListTile(title: Text('Developer'), subtitle: Text('Developed by Shartendu')),
      ]),
    );
  }
}

class _HomeModeCard extends StatelessWidget {
  const _HomeModeCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0, color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE0E8ED))),
    child: InkWell(
      borderRadius: BorderRadius.circular(18), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        CircleAvatar(radius: 24, backgroundColor: const Color(0xFFE6F5F3), foregroundColor: const Color(0xFF168B87), child: Icon(icon)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF687987), fontSize: 12)),
        ])),
        const Icon(Icons.chevron_right_rounded),
      ])),
    ),
  );
}

class OnlineRoomPage extends StatefulWidget {
  const OnlineRoomPage({super.key, required this.playerName});
  final String playerName;
  @override
  State<OnlineRoomPage> createState() => _OnlineRoomPageState();
}

class _OnlineRoomPageState extends State<OnlineRoomPage> {
  late final FirebaseRoomService _service;
  RoomSnapshot? _room;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _gameSub;
  bool _gameOpened = false;
  int _target = 150;
  bool _customTarget = false;
  final _customTargetController = TextEditingController(text: '175');

  @override
  void initState() { super.initState(); _service = FirebaseRoomService(apiKey: firebaseApiKey, databaseUrl: firebaseDatabaseUrl); }
  @override
  void dispose() { _code.dispose(); _customTargetController.dispose(); unawaited(_gameSub?.cancel()); unawaited(_service.dispose()); super.dispose(); }

  int? get _effectiveTarget => _customTarget
      ? int.tryParse(_customTargetController.text.trim())
      : _target;

  Future<void> _createOnlineRoom() async {
    final target = _effectiveTarget;
    if (target == null || target <= 0) {
      setState(() => _error = 'Custom Target Score शून्य से बड़ा अंक होना चाहिए।');
      return;
    }
    await _run(() => _service.createRoom(playerName: widget.playerName, targetScore: target));
  }

  Future<void> _run(Future<RoomSnapshot> Function() task) async {
    setState(() { _busy = true; _error = null; });
    try { final room = await task(); if (mounted) { setState(() { _room = room; _busy = false; }); if (room.hostId != _service.userId) _watchOnlineGame(room.code); } }
    catch (e) { if (mounted) setState(() { _error = e.toString().replaceFirst('Bad state: ', ''); _busy = false; }); }
  }

  void _watchOnlineGame(String code) {
    unawaited(_gameSub?.cancel());
    _gameSub = _service.watchGame(code).listen((message) {
      if (!mounted || _gameOpened || message['type'] != 'game') return;
      _gameOpened = true;
      Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteGameTablePage(
        messages: _service.watchGame(code),
        sendAction: (action) => unawaited(_service.sendAction(code, action)),
        playerId: _service.userId!,
        initialMessage: message,
        voiceRoomCode: code,
        getFirebaseIdToken: _service.getCurrentIdToken,
      )));
    }, onError: (Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  Future<void> _startOnlineGame() async {
    final room = _room;
    if (room == null || room.hostId != _service.userId || room.players.length < 2) return;
    setState(() { _busy = true; _error = null; });
    try {
      final engine = ScottGameEngine();
      final participants = room.players.map((p) => (id: p.id, name: p.name)).toList();
      final state = engine.startGame(participants: participants, targetScore: room.targetScore);
      await _service.publishGameState(room.code, GameStateCodec.publicState(state), GameStateCodec.privateHands(state));
      final actions = _service.watchActions(room.code).asyncExpand((items) => Stream<RoomAction>.fromIterable(items.map((item) => (
        playerId: item['playerId'] as String,
        action: Map<String, dynamic>.from(item['action'] as Map),
      ))));
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.push(context, MaterialPageRoute(builder: (_) => HostGameTablePage(
        engine: engine,
        initialState: state,
        hostId: _service.userId!,
        actions: actions,
        publish: (publicState, privateHands) => _service.publishGameState(room.code, publicState, privateHands),
        sendToPlayer: (_, __) {},
        voiceRoomCode: room.code,
        getFirebaseIdToken: _service.getCurrentIdToken,
      )));
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Online Multiplayer')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      if (_room == null) ...[
        const Text('नया ऑनलाइन कमरा', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('कमरा बनाइए और दोस्तों को 6 अक्षर का Room Code भेजिए।'),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _customTarget ? -1 : _target,
          decoration: const InputDecoration(labelText: 'Target Score'),
          items: const [100, 150, 200, -1].map((v) => DropdownMenuItem(value: v, child: Text(v == -1 ? 'Custom' : '$v अंक'))).toList(),
          onChanged: (v) => setState(() { _customTarget = v == -1; if (v != null && v > 0) _target = v; }),
        ),
        if (_customTarget) ...[
          const SizedBox(height: 10),
          TextField(controller: _customTargetController, keyboardType: TextInputType.number, maxLength: 5, decoration: const InputDecoration(labelText: 'Custom Target Score', hintText: 'जैसे 175')),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _createOnlineRoom, icon: const Icon(Icons.add_circle_outline), label: const Text('Create Room')),
        const Divider(height: 34),
        const Text('मौजूदा कमरे में शामिल हों', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _code, textCapitalization: TextCapitalization.characters, maxLength: 6, decoration: const InputDecoration(labelText: '6 अक्षर का Room Code')),
        FilledButton.tonalIcon(onPressed: _busy ? null : () => _run(() => _service.joinRoom(code: _code.text.trim(), playerName: widget.playerName)), icon: const Icon(Icons.login), label: const Text('Join Room')),
      ] else ...[
        _RoomHeader(room: _room!),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Share.share('क्या आप ससम्मान बाहर होने के लिए तैयार हैं? 😄\nतो आइए मेरे साथ SCOTT Game के मैदान में!\n\n🎮 गेम खेलने के लिए इस लिंक को खोलें:\nhttps://stenogpk.github.io/Scott/?room=${_room!.code}\n\nजुड़ने का तरीका:\n1. लिंक खोलें—गेम आपके ब्राउज़र में खुलेगा।\n2. अपना नाम दर्ज करें।\n3. Join Room दबाएँ और खेल शुरू करें!\n\nलक्ष्य: ${_room!.targetScore} अंक।'),
          icon: const Icon(Icons.share),
          label: const Text('Share Room / Invite Friends'),
        ),
        const SizedBox(height: 16),
        _PlayerList(players: _room!.players),
        if (_room!.hostId == _service.userId) ...[
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy || _room!.players.length < 2 ? null : _startOnlineGame, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start Game')),
        ],
        const SizedBox(height: 14),
        const Text('कमरे में 2 से 5 खिलाड़ी जुड़ सकते हैं।'),
        const SizedBox(height: 12),
        StreamBuilder<RoomSnapshot>(
          stream: _service.watchRoom(_room!.code),
          builder: (context, snap) {
            if (snap.hasData && snap.data!.players.length != _room!.players.length) {
              WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _room = snap.data); });
            }
            return Text('Connected players: ${snap.data?.players.length ?? _room!.players.length}/5');
          },
        ),
      ],
      if (_busy) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 18),
      const Text('ऑनलाइन खेलने के लिए SCOTT Firebase project का secure configuration जरूरी है।', style: TextStyle(color: Color(0xFF657583), fontSize: 12)),
    ])),
  );
}

class LocalWifiPage extends StatefulWidget {
  const LocalWifiPage({super.key, required this.playerName});
  final String playerName;
  @override
  State<LocalWifiPage> createState() => _LocalWifiPageState();
}

class _LocalWifiPageState extends State<LocalWifiPage> {
  final _server = LocalRoomServer();
  final _client = LocalRoomClient();
  final _actions = StreamController<({String playerId, Map<String, dynamic> action})>.broadcast();
  bool _gameOpened = false;
  int _target = 150;
  bool _customTarget = false;
  final _customTargetController = TextEditingController(text: '175');
  final _ip = TextEditingController();
  final _code = TextEditingController();
  String? _hostIp;
  RoomSnapshot? _room;
  String? _error;
  bool _busy = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_server.close());
    unawaited(_client.dispose());
    unawaited(_actions.close());
    _ip.dispose();
    _code.dispose();
    _customTargetController.dispose();
    super.dispose();
  }

  Future<String?> _findIp() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    // Prefer Android Wi-Fi / hotspot interfaces over mobile-data interfaces.
    final ordered = [...interfaces]..sort((a, b) {
      int priority(String name) {
        final value = name.toLowerCase();
        if (value.contains('wlan') || value.contains('wifi') || value.contains('ap')) return 0;
        if (value.contains('eth')) return 1;
        return 2;
      }
      return priority(a.name).compareTo(priority(b.name));
    });
    for (final interface in ordered) {
      for (final address in interface.addresses) {
        final ip = address.address;
        final parts = ip.split('.');
        final secondOctet = parts.length > 1 ? int.tryParse(parts[1]) : null;
        final isPrivate172 = parts.first == '172' &&
            secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
        if (ip.startsWith('192.168.') || ip.startsWith('10.') || isPrivate172) {
          return ip;
        }
      }
    }
    return null;
  }

  Future<void> _host() async {
    final target = _customTarget
        ? int.tryParse(_customTargetController.text.trim())
        : _target;
    if (target == null || target <= 0) {
      setState(() => _error = 'Custom Target Score शून्य से बड़ा अंक होना चाहिए।');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final ip = await _findIp();
      if (ip == null) throw StateError('Wi-Fi IP नहीं मिला। दोनों फोन को एक ही Wi-Fi या Hotspot से जोड़ें।');
      final code = await _server.start(hostName: widget.playerName, targetScore: target, onRoomChanged: (room) { if (mounted) setState(() => _room = room); }, onAction: (playerId, action) => _actions.add((playerId: playerId, action: action)));
      if (mounted) setState(() { _hostIp = ip; _room = RoomSnapshot(code: code, hostId: _server.players.first.id, players: _server.players, targetScore: target); _busy = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  void _startLocalGame() {
    if (_server.players.length < 2) return;
    final engine = ScottGameEngine();
    final participants = _server.players.map((p) => (id: p.id, name: p.name)).toList();
    final state = engine.startGame(participants: participants, targetScore: _room?.targetScore ?? _target);
    Navigator.push(context, MaterialPageRoute(builder: (_) => HostGameTablePage(
      engine: engine,
      initialState: state,
      hostId: _server.players.first.id,
      actions: _actions.stream,
      publish: (publicState, privateHands) async => _server.updateGameState(publicState, privateHands: privateHands),
      sendToPlayer: _server.sendToPlayer,
    )));
  }

  Future<void> _join() async {
    setState(() { _busy = true; _error = null; });
    try {
      // Subscribe before the join packet is sent so the initial welcome/room
      // messages cannot race ahead of the UI listener.
      _sub = _client.messages.listen((message) {
        if (!mounted) return;
        if (message['type'] == 'room') setState(() => _room = RoomSnapshot.fromJson(Map<String, dynamic>.from(message['room'] as Map)));
        if (message['type'] == 'welcome') setState(() => _room = RoomSnapshot.fromJson(Map<String, dynamic>.from(message['room'] as Map)));
        if (message['type'] == 'error') setState(() => _error = message['message'] as String?);
        if (message['type'] == 'game' && !_gameOpened && _client.playerId != null) {
          _gameOpened = true;
          Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteGameTablePage(messages: _client.messages, sendAction: _client.sendAction, playerId: _client.playerId!, initialMessage: message)));
        }
      });
      await _client.connect(hostAddress: _ip.text.trim(), roomCode: _code.text.trim(), playerName: widget.playerName);
      if (mounted) setState(() => _busy = false);
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local Wi-Fi Multiplayer')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      if (_room == null) ...[
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('नया Local Room बनाएँ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('यह फोन Host बनेगा। दूसरे खिलाड़ी इसी Wi-Fi या आपके Hotspot से जुड़ेंगे।'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _customTarget ? -1 : _target,
            decoration: const InputDecoration(labelText: 'Target Score'),
            items: const [100, 150, 200, -1].map((v) => DropdownMenuItem(value: v, child: Text(v == -1 ? 'Custom' : '$v अंक'))).toList(),
            onChanged: (v) => setState(() { _customTarget = v == -1; if (v != null && v > 0) _target = v; }),
          ),
          if (_customTarget) ...[
            const SizedBox(height: 10),
            TextField(controller: _customTargetController, keyboardType: TextInputType.number, maxLength: 5, decoration: const InputDecoration(labelText: 'Custom Target Score', hintText: 'जैसे 175')),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _host, icon: const Icon(Icons.wifi_tethering), label: const Text('Create Local Room')),
        ]))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Room में Join करें', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          TextField(controller: _ip, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Host का Wi-Fi IP (जैसे 192.168.1.5)')),
          const SizedBox(height: 10),
          TextField(controller: _code, textCapitalization: TextCapitalization.characters, maxLength: 6, decoration: const InputDecoration(labelText: 'Room Code')),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _join, icon: const Icon(Icons.login), label: const Text('Join Local Room')),
        ]))),
      ] else ...[
        _RoomHeader(room: _room!),
        if (_hostIp != null) SelectableText('Host IP: $_hostIp : ${_server.port}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _PlayerList(players: _room!.players),
        const SizedBox(height: 12),
        const Text('दूसरे फोन में Host IP और Room Code डालकर Join करें। सभी फोन एक ही Wi-Fi / Hotspot पर होने चाहिए।'),
        if (_hostIp != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _room!.players.length < 2 ? null : _startLocalGame,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Game'),
          ),
        ],
      ],
      if (_busy) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
    ])),
  );
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});
  final RoomSnapshot room;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: const Color(0xFF142B45), borderRadius: BorderRadius.circular(18)),
    child: Column(children: [
      const Text('ROOM CODE', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 2)),
      const SizedBox(height: 6),
      SelectableText(room.code, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 5)),
      const SizedBox(height: 6),
      Text('Target: ${room.targetScore} अंक', style: const TextStyle(color: Colors.white70)),
    ]),
  );
}

class _PlayerList extends StatelessWidget {
  const _PlayerList({required this.players});
  final List<RoomPlayer> players;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('खिलाड़ी', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (var i = 0; i < players.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(players[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: players[i].isHost
              ? const Chip(label: Text('HOST'))
              : players[i].isConnected
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Chip(label: Text('DISCONNECTED'), backgroundColor: Color(0xFFFFE0E0)),
        ),
    ])),
  );
}
