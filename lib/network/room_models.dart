class RoomPlayer {
  const RoomPlayer({required this.id, required this.name, this.isHost = false, this.isConnected = true, this.isReady = false, this.lastSeenAt = 0, this.lastActionAt = 0, this.leftAt = 0});
  final String id;
  final String name;
  final bool isHost;
  final bool isConnected;
  final bool isReady;
  final int lastSeenAt;
  final int lastActionAt;
  final int leftAt;
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'isHost': isHost, 'isConnected': isConnected, 'isReady': isReady, 'lastSeenAt': lastSeenAt, 'lastActionAt': lastActionAt, 'leftAt': leftAt};
  factory RoomPlayer.fromJson(Map<String, dynamic> json) => RoomPlayer(
    id: json['id'] as String, name: json['name'] as String,
    isHost: json['isHost'] as bool? ?? false,
    isConnected: json['isConnected'] as bool? ?? true,
    isReady: json['isReady'] as bool? ?? false,
    lastSeenAt: json['lastSeenAt'] as int? ?? 0,
    lastActionAt: json['lastActionAt'] as int? ?? 0,
    leftAt: json['leftAt'] as int? ?? 0,
  );
}

class RoomSnapshot {
  const RoomSnapshot({required this.code, required this.hostId, required this.players, this.targetScore = 150, this.started = false, this.gameState, this.updatedAt});
  final String code;
  final String hostId;
  final List<RoomPlayer> players;
  final int targetScore;
  final bool started;
  final Map<String, dynamic>? gameState;
  final int? updatedAt;

  Map<String, Object?> toJson() => {
    'code': code, 'hostId': hostId,
    'players': {for (final player in players) player.id: player.toJson()},
    'targetScore': targetScore, 'started': started,
    if (gameState != null) 'gameState': gameState,
    'updatedAt': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
  };

  factory RoomSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['players'];
    final players = raw is Map
        ? raw.values.whereType<Map>().map((v) => RoomPlayer.fromJson(Map<String, dynamic>.from(v))).toList()
        : <RoomPlayer>[];
    return RoomSnapshot(
      code: json['code'] as String, hostId: json['hostId'] as String,
      players: List.unmodifiable(players),
      targetScore: json['targetScore'] as int? ?? 150,
      started: json['started'] as bool? ?? false,
      gameState: json['gameState'] is Map ? Map<String, dynamic>.from(json['gameState'] as Map) : null,
      updatedAt: json['updatedAt'] as int?,
    );
  }
}
