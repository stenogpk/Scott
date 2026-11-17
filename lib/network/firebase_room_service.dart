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
  String? _userId;

  bool get isConfigured => apiKey.isNotEmpty && databaseUrl.startsWith('https://');

  Future<void> signInAsGuest() async {
    if (!isConfigured) throw StateError('Online multiplayer setup is incomplete. Firebase API key and Realtime Database URL are required.');
    final uri = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
    final response = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'returnSecureToken': true}));
    if (response.statusCode != 200) throw StateError('Guest sign-in failed: ${response.body}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _idToken = json['idToken'] as String;
    _userId = json['localId'] as String;
  }

  Future<RoomSnapshot> createRoom({required String playerName, int targetScore = 150}) async {
    await _ensureSignedIn();
    final code = _newRoomCode();
    final hostId = _userId!;
    final snapshot = RoomSnapshot(code: code, hostId: hostId, players: [RoomPlayer(id: hostId, name: playerName.trim(), isHost: true)], targetScore: targetScore);
    final response = await _client.put(_roomUri(code), headers: {'Content-Type': 'application/json'}, body: jsonEncode(snapshot.toJson()));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Room create failed: ${response.body}');
    return snapshot;
  }

  Future<RoomSnapshot> joinRoom({required String code, required String playerName}) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.started) throw StateError('यह गेम शुरू हो चुका है।');
    if (room.players.length >= 5) throw StateError('कमरा भर चुका है।');
    if (room.players.any((p) => p.id == _userId)) return room;
    final players = [...room.players, RoomPlayer(id: _userId!, name: playerName.trim())];
    final updated = RoomSnapshot(code: room.code, hostId: room.hostId, players: players, targetScore: room.targetScore, started: room.started, gameState: room.gameState);
    await _putRoom(updated);
    return updated;
  }

  Future<RoomSnapshot> getRoom(String code) async {
    await _ensureSignedIn();
    final response = await _client.get(_roomUri(code), headers: {'Accept': 'application/json'});
    if (response.statusCode != 200) throw StateError('Room lookup failed: ${response.body}');
    final raw = jsonDecode(response.body);
    if (raw == null) throw StateError('यह Room Code नहीं मिला।');
    return RoomSnapshot.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> publishGameState(String code, Map<String, dynamic> publicState) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.hostId != _userId) throw StateError('Only the room host can publish the game state.');
    final updated = RoomSnapshot(code: room.code, hostId: room.hostId, players: room.players, targetScore: room.targetScore, started: true, gameState: publicState);
    await _putRoom(updated);
  }

  Stream<RoomSnapshot> watchRoom(String code, {Duration interval = const Duration(seconds: 2)}) async* {
    await _ensureSignedIn();
    yield await getRoom(code);
    yield* Stream.periodic(interval).asyncMap((_) => getRoom(code));
  }

  Future<void> _putRoom(RoomSnapshot snapshot) async {
    final response = await _client.put(_roomUri(snapshot.code), headers: {'Content-Type': 'application/json'}, body: jsonEncode(snapshot.toJson()));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Room update failed: ${response.body}');
  }

  Uri _roomUri(String code) => Uri.parse('${databaseUrl.replaceFirst(RegExp(r'/+$'), '')}/rooms/${code.toUpperCase()}.json?auth=$_idToken');

  Future<void> _ensureSignedIn() async {
    if (_idToken == null || _userId == null) await signInAsGuest();
  }

  String _newRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> dispose() async => _client.close();
}
