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
  String? get userId => _userId;

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
    final player = RoomPlayer(id: hostId, name: playerName.trim(), isHost: true);
    await _putPath('rooms/$code/hostId', jsonEncode(hostId));
    await _putPath('rooms/$code/targetScore', jsonEncode(targetScore));
    await _putPath('rooms/$code/started', 'false');
    await _putPath('rooms/$code/updatedAt', jsonEncode(DateTime.now().millisecondsSinceEpoch));
    await _putPath('rooms/$code/players/$hostId', jsonEncode(player.toJson()));
    return RoomSnapshot(code: code, hostId: hostId, players: [player], targetScore: targetScore);
  }

  Future<RoomSnapshot> joinRoom({required String code, required String playerName}) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.started) throw StateError('यह गेम शुरू हो चुका है।');
    if (room.players.length >= 5) throw StateError('कमरा भर चुका है।');
    if (room.players.any((p) => p.id == _userId)) return room;
    final player = RoomPlayer(id: _userId!, name: playerName.trim());
    await _putPath('rooms/${room.code}/players/${player.id}', jsonEncode(player.toJson()));
    await _putPath('rooms/${room.code}/updatedAt', jsonEncode(DateTime.now().millisecondsSinceEpoch));
    return RoomSnapshot(code: room.code, hostId: room.hostId, players: [...room.players, player], targetScore: room.targetScore);
  }

  Future<RoomSnapshot> getRoom(String code) async {
    await _ensureSignedIn();
    final response = await _client.get(_roomUri(code), headers: {'Accept': 'application/json'});
    if (response.statusCode != 200) throw StateError('Room lookup failed: ${response.body}');
    final raw = jsonDecode(response.body);
    if (raw == null) throw StateError('यह Room Code नहीं मिला।');
    return RoomSnapshot.fromJson(Map<String, dynamic>.from(raw as Map)..['code'] = code.toUpperCase());
  }

  Future<void> publishGameState(String code, Map<String, dynamic> publicState) async {
    await _ensureSignedIn();
    final room = await getRoom(code);
    if (room.hostId != _userId) throw StateError('Only the room host can publish the game state.');
    await _putPath('rooms/${room.code}/gameState', jsonEncode(publicState));
    await _putPath('rooms/${room.code}/started', 'true');
    await _putPath('rooms/${room.code}/updatedAt', jsonEncode(DateTime.now().millisecondsSinceEpoch));
  }

  Stream<RoomSnapshot> watchRoom(String code, {Duration interval = const Duration(seconds: 2)}) async* {
    await _ensureSignedIn();
    yield await getRoom(code);
    yield* Stream.periodic(interval).asyncMap((_) => getRoom(code));
  }

  Future<void> _putPath(String path, String body) async {
    final uri = Uri.parse('${databaseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path.json?auth=$_idToken');
    final response = await _client.put(uri, headers: {'Content-Type': 'application/json'}, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Firebase write failed: ${response.body}');
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
