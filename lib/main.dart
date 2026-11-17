// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'network/firebase_room_service.dart';
import 'network/local_room_client.dart';
import 'network/local_room_server.dart';
import 'network/room_models.dart';

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
    home: const ScottHomePage(),
  );
}

class ScottHomePage extends StatefulWidget {
  const ScottHomePage({super.key});
  @override
  State<ScottHomePage> createState() => _ScottHomePageState();
}

class _ScottHomePageState extends State<ScottHomePage> {
  final _name = TextEditingController();
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SCOTT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))),
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
          TextField(controller: _name, textCapitalization: TextCapitalization.words, maxLength: 18, decoration: const InputDecoration(labelText: 'आपका खिलाड़ी नाम', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          _HomeModeCard(icon: Icons.public, title: 'Online Multiplayer', subtitle: 'दूर बैठे दोस्तों के साथ Room Code से खेलें', onTap: () => _open(context, OnlineRoomPage(playerName: _playerName))),
          const SizedBox(height: 12),
          _HomeModeCard(icon: Icons.wifi, title: 'Local Wi-Fi Multiplayer', subtitle: 'एक ही Wi-Fi / Hotspot पर, इंटरनेट के बिना', onTap: () => _open(context, LocalWifiPage(playerName: _playerName))),
          const SizedBox(height: 18),
          const Text('खेल में 2–5 खिलाड़ी • 52 पत्ते • नौकी (9) शून्य अंक', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF607080))),
          const SizedBox(height: 14),
          const Text('Developed by Shartendu', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7B89), fontWeight: FontWeight.w700)),
        ],
      )),
    ))),
  );

  String get _playerName => _name.text.trim().isEmpty ? 'खिलाड़ी' : _name.text.trim();
  void _open(BuildContext context, Widget page) {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पहले अपना खिलाड़ी नाम लिखें।')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
  bool _busy = false;
  String? _error;
  int _target = 150;

  @override
  void initState() { super.initState(); _service = FirebaseRoomService(apiKey: firebaseApiKey, databaseUrl: firebaseDatabaseUrl); }
  @override
  void dispose() { unawaited(_service.dispose()); super.dispose(); }

  Future<void> _run(Future<RoomSnapshot> Function() task) async {
    setState(() { _busy = true; _error = null; });
    try { final room = await task(); if (mounted) setState(() { _room = room; _busy = false; }); }
    catch (e) { if (mounted) setState(() { _error = e.toString().replaceFirst('Bad state: ', ''); _busy = false; }); }
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
        DropdownButtonFormField<int>(value: _target, decoration: const InputDecoration(labelText: 'Target Score'), items: const [100,150,200].map((v) => DropdownMenuItem(value: v, child: Text('$v अंक'))).toList(), onChanged: (v) => setState(() => _target = v ?? 150)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : () => _run(() => _service.createRoom(playerName: widget.playerName, targetScore: _target)), icon: const Icon(Icons.add_circle_outline), label: const Text('Create Room')),
        const Divider(height: 34),
        const Text('मौजूदा कमरे में शामिल हों', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: _code, textCapitalization: TextCapitalization.characters, maxLength: 6, decoration: const InputDecoration(labelText: '6 अक्षर का Room Code')),
        FilledButton.tonalIcon(onPressed: _busy ? null : () => _run(() => _service.joinRoom(code: _code.text.trim(), playerName: widget.playerName)), icon: const Icon(Icons.login), label: const Text('Join Room')),
      ] else ...[
        _RoomHeader(room: _room!),
        const SizedBox(height: 16),
        _PlayerList(players: _room!.players),
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
    _ip.dispose();
    super.dispose();
  }

  Future<String?> _findIp() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.startsWith('192.168.') || address.address.startsWith('10.') || address.address.startsWith('172.')) return address.address;
      }
    }
    return null;
  }

  Future<void> _host() async {
    setState(() { _busy = true; _error = null; });
    try {
      final ip = await _findIp();
      if (ip == null) throw StateError('Wi-Fi IP नहीं मिला। दोनों फोन को एक ही Wi-Fi या Hotspot से जोड़ें।');
      final code = await _server.start(hostName: widget.playerName, onRoomChanged: (room) { if (mounted) setState(() => _room = room); });
      if (mounted) setState(() { _hostIp = ip; _room = RoomSnapshot(code: code, hostId: _server.players.first.id, players: _server.players); _busy = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  Future<void> _join() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _client.connect(hostAddress: _ip.text.trim(), playerName: widget.playerName);
      _sub = _client.messages.listen((message) {
        if (!mounted) return;
        if (message['type'] == 'room') setState(() => _room = RoomSnapshot.fromJson(Map<String, dynamic>.from(message['room'] as Map)));
        if (message['type'] == 'welcome') setState(() => _room = RoomSnapshot.fromJson(Map<String, dynamic>.from(message['room'] as Map)));
        if (message['type'] == 'error') setState(() => _error = message['message'] as String?);
      });
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
          FilledButton.icon(onPressed: _busy ? null : _host, icon: const Icon(Icons.wifi_tethering), label: const Text('Create Local Room')),
        ]))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Room में Join करें', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          TextField(controller: _ip, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Host का Wi-Fi IP (जैसे 192.168.1.5)')),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _join, icon: const Icon(Icons.login), label: const Text('Join Local Room')),
        ]))),
      ] else ...[
        _RoomHeader(room: _room!),
        if (_hostIp != null) SelectableText('Host IP: $_hostIp : ${_server.port}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _PlayerList(players: _room!.players),
        const SizedBox(height: 12),
        const Text('दूसरे फोन में Host IP डालकर Join करें। सभी फोन एक ही Wi-Fi / Hotspot पर होने चाहिए।'),
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
          trailing: players[i].isHost ? const Chip(label: Text('HOST')) : const Icon(Icons.check_circle, color: Colors.green),
        ),
    ])),
  );
}
