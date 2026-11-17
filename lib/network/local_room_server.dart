import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'room_models.dart';

class LocalRoomServer {
  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  final Map<String, RoomPlayer> _players = {};
  String? _hostId;
  String? _roomCode;
  int _targetScore = 150;
  Map<String, dynamic>? _gameState;
  String? get roomCode => _roomCode;
  int get port => _server?.port ?? 0;
  List<RoomPlayer> get players => List.unmodifiable(_players.values);

  Future<String> start({required String hostName, int targetScore = 150, int preferredPort = 8765, void Function(RoomSnapshot)? onRoomChanged, void Function(String, Map<String, dynamic>)? onAction}) async {
    if (_server != null) throw StateError('Room server is already running.');
    _hostId = _randomId();
    _roomCode = _newRoomCode();
    _targetScore = targetScore;
    _players[_hostId!] = RoomPlayer(id: _hostId!, name: hostName.trim(), isHost: true);
    _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    _server!.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response..statusCode = HttpStatus.ok..write('SCOTT local room')..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _clients.add(socket);
      socket.listen((raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (msg['type'] == 'join') {
            final id = msg['id'] as String? ?? _randomId();
            final name = (msg['name'] as String? ?? 'खिलाड़ी').trim();
            if (_players.length >= 5 || _players.containsKey(id)) {
              socket.add(jsonEncode({'type': 'error', 'message': 'कमरा भर चुका है।'}));
              socket.close();
              return;
            }
            _players[id] = RoomPlayer(id: id, name: name);
            socket.add(jsonEncode({'type': 'welcome', 'playerId': id, 'room': _snapshot().toJson()}));
            _broadcast({'type': 'room', 'room': _snapshot().toJson()});
            onRoomChanged?.call(_snapshot());
          } else if (msg['type'] == 'action') {
            final id = msg['playerId'] as String?;
            if (id != null && _players.containsKey(id) && msg['action'] is Map) {
              onAction?.call(id, Map<String, dynamic>.from(msg['action'] as Map));
            }
          } else if (msg['type'] == 'ready') {
            final id = msg['playerId'] as String?;
            if (id != null && _players.containsKey(id)) {
              final old = _players[id]!;
              _players[id] = RoomPlayer(id: old.id, name: old.name, isHost: old.isHost, isConnected: true, isReady: msg['ready'] == true);
              _broadcast({'type': 'room', 'room': _snapshot().toJson()});
              onRoomChanged?.call(_snapshot());
            }
          }
        } catch (_) {
          socket.add(jsonEncode({'type': 'error', 'message': 'गलत संदेश मिला।'}));
        }
      }, onDone: () {
        _clients.remove(socket);
        _broadcast({'type': 'room', 'room': _snapshot().toJson()});
        onRoomChanged?.call(_snapshot());
      }, onError: (_) => _clients.remove(socket));
    });
    return _roomCode!;
  }

  void updateGameState(Map<String, dynamic> state) {
    _gameState = state;
    _broadcast({'type': 'game', 'state': state});
  }
  void setTargetScore(int value) {
    if (value <= 0) throw ArgumentError.value(value);
    _targetScore = value;
    _broadcast({'type': 'room', 'room': _snapshot().toJson()});
  }
  RoomSnapshot _snapshot() => RoomSnapshot(code: _roomCode!, hostId: _hostId!, players: players, targetScore: _targetScore, started: _gameState != null, gameState: _gameState);
  void _broadcast(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    for (final socket in _clients.toList()) {
      if (socket.readyState == WebSocket.open) socket.add(data);
    }
  }
  Future<void> close() async {
    for (final socket in _clients.toList()) { await socket.close(); }
    _clients.clear();
    await _server?.close(force: true);
    _server = null; _players.clear(); _roomCode = null; _hostId = null; _gameState = null;
  }
  String _newRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
  String _randomId() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
}
