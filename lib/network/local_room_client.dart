import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalRoomClient {
  WebSocket? _socket;
  String? playerId;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  Future<void> connect({required String hostAddress, int port = 8765, required String playerName}) async {
    if (_socket != null) throw StateError('Already connected to a room.');
    final socket = await WebSocket.connect('ws://${hostAddress.trim()}:$port');
    _socket = socket;
    socket.listen((raw) {
      final message = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
      if (message['type'] == 'welcome') playerId = message['playerId'] as String;
      _messages.add(message);
    }, onDone: () => _messages.add({'type': 'disconnected'}), onError: (Object e) => _messages.add({'type': 'error', 'message': e.toString()}));
    socket.add(jsonEncode({'type': 'join', 'id': 'guest-${DateTime.now().microsecondsSinceEpoch}', 'name': playerName.trim()}));
  }

  void sendAction(Map<String, dynamic> action) => _send({'type': 'action', 'playerId': playerId, 'action': action});
  void setReady(bool ready) => _send({'type': 'ready', 'playerId': playerId, 'ready': ready});
  void _send(Map<String, dynamic> msg) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) throw StateError('Room connection is not active.');
    socket.add(jsonEncode(msg));
  }
  Future<void> disconnect() async { await _socket?.close(); _socket = null; playerId = null; }
  Future<void> dispose() async { await disconnect(); await _messages.close(); }
}
