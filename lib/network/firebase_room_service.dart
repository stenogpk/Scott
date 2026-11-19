import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'room_models.dart';

class FirebaseRoomService {
  FirebaseRoomService({required this.apiKey, required this.databaseUrl, http.Client? client})
      : _client = client ?? http.Client();
  final String apiKey;
  final String databaseUrl;
  final http.Client _client;
  String? _idToken;
  String? _refreshToken;
  String? _userId;
  DateTime? _tokenExpiresAt;
  String? get userId => _userId;
  bool get isConfigured => apiKey.isNotEmpty && databaseUrl.startsWith('https://');

  Future<void> signInAsGuest() async {
    if (!isConfigured) throw StateError('Online multiplayer setup is incomplete. Firebase API key and Realtime Database URL are required.');
    final uri = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
    final response = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'returnSecureToken': true}));
    if (response.statusCode != 200) throw StateError('Guest sign-in failed: ${response.body}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _idToken = json['idToken'] as String;
    _refreshToken = json['refreshToken'] as String?;
    _userId = json['localId'] as String;
    final expiresIn = int.tryParse(json['expiresIn']?.toString() ?? '') ?? 3600;
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  }

  Future<RoomSnapshot> createRoom({required String playerName, int targetScore = 150}) async {
    await _ensureSignedIn();
    final code = _newRoomCode();
    final hostId = _userId!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final player = RoomPlayer(id: hostId, name: playerName.trim(), isHost: true, lastSeenAt: now, lastActionAt: now);
    await _putPath('rooms/$code/public/hostId', jsonEncode(hostId));
    await _putPath('rooms/$code/public/code', jsonEncode(code));
    await _putPath('rooms/$code/public/targetScore', jsonEncode(targetScore));
    await _putPath('rooms/$code/public/started', 'false');
    await _putPath('rooms/$code/public/updatedAt', jsonEncode(DateTime.now().millisecondsSinceEpoch));
    await _putPath('rooms/$code/public/players/$hostId', jsonEncode(player.toJson()));
    return RoomSnapshot(code: code, hostId: hostId, players: [player], targetScore: targetScore);
  }

  Future<RoomSnapshot> joinRoom({required String code, required String playerName}) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.started) throw StateError('यह गेम शुरू हो चुका है।');
    if (room.players.length >= 5) throw StateError('कमरा भर चुका है।');
    if (room.players.any((p) => p.id == _userId)) return room;
    final now = DateTime.now().millisecondsSinceEpoch;
    final player = RoomPlayer(id: _userId!, name: playerName.trim(), lastSeenAt: now, lastActionAt: now);
    // A joining guest may add only their own player record. updatedAt is
    // host-owned in the database rules, so writing it here caused every join
    // to fail with PERMISSION_DENIED after the player record was created.
    await _putPath('rooms/${room.code}/public/players/${player.id}', jsonEncode(player.toJson()));
    return RoomSnapshot(code: room.code, hostId: room.hostId, players: [...room.players, player], targetScore: room.targetScore);
  }

  Future<RoomSnapshot> getRoom(String code) async {
    await _ensureSignedIn();
    final response = await _client.get(_pathUri('rooms/${code.toUpperCase()}/public'));
    if (response.statusCode != 200) throw StateError('Room lookup failed: ${response.body}');
    final raw = jsonDecode(response.body);
    if (raw == null) throw StateError('यह Room Code नहीं मिला।');
    return RoomSnapshot.fromJson(Map<String, dynamic>.from(raw as Map)..['code'] = code.toUpperCase());
  }

  Future<void> publishGameState(String code, Map<String, dynamic> publicState, Map<String, List<Map<String, dynamic>>> privateHands) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.hostId != _userId) throw StateError('Only the room host can publish the game state.');
    final hostPlayer = room.players.where((p) => p.id == _userId).toList();
    if (hostPlayer.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _putPath('rooms/${room.code}/public/players/${_userId!}', jsonEncode({...hostPlayer.first.toJson(), 'lastSeenAt': now, 'lastActionAt': now, 'isConnected': true, 'leftAt': 0}));
    }
    for (final entry in privateHands.entries) {
      await _putPath('rooms/${room.code}/privateHands/${entry.key}', jsonEncode(entry.value));
    }
    await _putPath('rooms/${room.code}/public/gameState', jsonEncode(publicState));
    await _putPath('rooms/${room.code}/public/started', 'true');
    await _putPath('rooms/${room.code}/public/updatedAt', jsonEncode(DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> updatePresence(String code, {bool active = true, bool userAction = false}) async {
    await _ensureSignedIn();
    final id = _userId!;
    final room = await getRoom(code);
    final matches = room.players.where((p) => p.id == id).toList();
    if (matches.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = matches.first;
    await _putPath('rooms/${room.code}/public/players/$id', jsonEncode({
      ...current.toJson(), 'isConnected': active, 'lastSeenAt': now,
      'lastActionAt': userAction ? now : current.lastActionAt, 'leftAt': active ? 0 : now,
    }));
  }

  Future<void> transferHost(String code, String newHostId) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.hostId != _userId) throw StateError('केवल वर्तमान Host ही Host बदल सकता है।');
    if (!room.players.any((p) => p.id == newHostId && p.isConnected && p.leftAt == 0)) {
      throw StateError('नया Host ऑनलाइन खिलाड़ी होना चाहिए।');
    }
    await _putPath('rooms/${room.code}/public/hostId', jsonEncode(newHostId));
    for (final player in room.players) {
      await _putPath('rooms/${room.code}/public/players/${player.id}', jsonEncode({...player.toJson(), 'isHost': player.id == newHostId}));
    }
  }

  Future<void> leaveRoom(String code) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    final id = _userId!;
    final alternatives = room.players.where((p) => p.id != id && p.isConnected && p.leftAt == 0).toList();
    if (room.hostId == id && alternatives.isNotEmpty) await transferHost(code, alternatives.first.id);
    await updatePresence(code, active: false);
  }

  Future<void> sendAction(String code, Map<String, dynamic> action) async {
    await _ensureSignedIn();
    final id = _userId!;
    await updatePresence(code, userAction: true);
    await _putPath('rooms/${code.toUpperCase()}/actions/$id', jsonEncode({
      'playerId': id,
      'action': action,
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  Stream<RoomSnapshot> watchRoom(String code, {Duration interval = const Duration(seconds: 2)}) async* {
    await _ensureSignedIn();
    yield await getRoom(code);
    yield* Stream.periodic(interval).asyncMap((_) => getRoom(code));
  }

  Stream<List<Map<String, dynamic>>> watchActions(String code, {Duration interval = const Duration(milliseconds: 800)}) async* {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.hostId != _userId) throw StateError('Only the host can receive player actions.');
    yield* Stream.periodic(interval).asyncMap((_) async {
      final response = await _client.get(_pathUri('rooms/${code.toUpperCase()}/actions'));
      if (response.statusCode != 200 || response.body == 'null') return <Map<String, dynamic>>[];
      final raw = jsonDecode(response.body) as Map;
      final actions = <Map<String, dynamic>>[];
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          actions.add(Map<String, dynamic>.from(entry.value as Map));
          await _deletePath('rooms/${code.toUpperCase()}/actions/${entry.key}');
        }
      }
      return actions;
    });
  }

  Stream<Map<String, dynamic>> watchGame(String code, {Duration interval = const Duration(seconds: 1)}) async* {
    await _ensureSignedIn();
    final id = _userId!;
    yield await _getGameMessage(code, id);
    yield* Stream.periodic(interval).asyncMap((_) => _getGameMessage(code, id));
  }

  Future<Map<String, dynamic>> _getGameMessage(String code, String id) async {
    final room = await getRoom(code);
    final state = room.gameState;
    if (state == null) return {'type': 'waiting'};
    final response = await _client.get(_pathUri('rooms/${code.toUpperCase()}/privateHands/$id'));
    final privateHand = response.statusCode == 200 && response.body != 'null' ? jsonDecode(response.body) : const [];
    return {'type': 'game', 'state': state, 'privateHand': privateHand};
  }

  Future<void> _putPath(String path, String body) async {
    final response = await _client.put(_pathUri(path), headers: {'Content-Type': 'application/json'}, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Firebase write failed: ${response.body}');
  }

  Future<void> _deletePath(String path) async {
    final response = await _client.delete(_pathUri(path));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Firebase action cleanup failed: ${response.body}');
  }

  Uri _pathUri(String path) => Uri.parse('${databaseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path.json?auth=$_idToken');

  Future<void> _ensureSignedIn() async {
    if (_idToken == null || _userId == null) {
      await signInAsGuest();
      return;
    }
    final expiresAt = _tokenExpiresAt;
    if (expiresAt == null || DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 2)))) {
      return;
    }
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('Online session expired. Please rejoin the room.');
    }
    final uri = Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    if (response.statusCode != 200) {
      throw StateError('Online session refresh failed. Please rejoin the room.');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _idToken = (json['id_token'] ?? json['idToken']) as String;
    _refreshToken = (json['refresh_token'] ?? json['refreshToken']) as String? ?? refreshToken;
    _userId = (json['user_id'] ?? json['localId']) as String? ?? _userId;
    final expiresIn = int.tryParse((json['expires_in'] ?? json['expiresIn'])?.toString() ?? '') ?? 3600;
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  }

  String _newRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> dispose() async => _client.close();
}
