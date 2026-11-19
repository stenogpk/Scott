// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../game/game_models.dart';
import '../game/playing_card.dart';
import '../game/scott_game_engine.dart';
import '../network/game_state_codec.dart';
import '../services/scott_audio.dart';
import '../game/commentary.dart';
import 'scott_rules_page.dart';
typedef RoomAction = ({String playerId, Map<String, dynamic> action});

class HostGameTablePage extends StatefulWidget {
  const HostGameTablePage({super.key, required this.engine, required this.initialState, required this.publish, required this.sendToPlayer, required this.hostId, required this.actions});
  final ScottGameEngine engine;
  final GameState initialState;
  final Future<void> Function(Map<String, dynamic>, Map<String, List<Map<String, dynamic>>>) publish;
  final void Function(String, Map<String, dynamic>) sendToPlayer;
  final String hostId;
  final Stream<RoomAction> actions;
  @override
  State<HostGameTablePage> createState() => _HostGameTablePageState();
}

class _HostGameTablePageState extends State<HostGameTablePage> {
  late GameState _state;
  RoundResult? _result;
  final Set<PlayingCard> _selected = {};
  final List<Map<String, dynamic>> _history = [];
  final ScottCommentary _commentary = ScottCommentary();
  late final ConfettiController _confetti;
  String? _commentaryText;
  Timer? _commentaryTimer;
  StreamSubscription<({String playerId, Map<String, dynamic> action})>? _actionsSub;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _confetti = ConfettiController(duration: const Duration(seconds: 4));
    unawaited(_publish());
    _actionsSub = widget.actions.listen((event) => _handleRemoteAction(event.playerId, event.action));
  }

  @override
  void dispose() {
    unawaited(_actionsSub?.cancel());
    _commentaryTimer?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _publish() {
    final publicState = GameStateCodec.publicState(_state, revealHands: _state.phase != GamePhase.waitingForTurn);
    publicState['history'] = List<Map<String, dynamic>>.from(_history);
    publicState['commentary'] = _commentaryText;
    if (_result != null) {
      publicState['roundResult'] = {
        'callerId': _result!.callerId, 'successful': _result!.wasSuccessful,
        'automatic': _result!.wasAutomatic, 'handTotals': _result!.handTotals,
        'pointsAdded': _result!.pointsAdded, 'eliminatedPlayerIds': _result!.eliminatedPlayerIds,
        'winnerId': _result!.winnerId,
      };
    } else { publicState.remove('roundResult'); }
    return widget.publish(publicState, GameStateCodec.privateHands(_state));
  }

  void _recordRound() {
    final result = _result;
    if (result == null || _history.any((entry) => entry['round'] == _state.roundNumber)) return;
    _history.add({
      'round': _state.roundNumber,
      'callerId': result.callerId,
      'successful': result.wasSuccessful,
      'automatic': result.wasAutomatic,
      'handTotals': result.handTotals,
      'pointsAdded': result.pointsAdded,
      'scores': {for (final player in _state.players) player.id: player.score},
      'eliminatedPlayerIds': result.eliminatedPlayerIds,
      'winnerId': result.winnerId,
    });
  }

  void _handleRemoteAction(String playerId, Map<String, dynamic> action) {
    if (!mounted || _state.phase != GamePhase.waitingForTurn || _state.currentPlayer.id != playerId) return;
    try {
      final type = action['type'];
      if (type == 'show') {
        final turn = widget.engine.show(_state, playerId);
        _state = turn.state;
        _result = turn.roundResult;
      } else if (type == 'discard') {
        final raw = action['cards'];
        if (raw is! List || raw.isEmpty) {
          throw StateError('Discard action must contain at least one card.');
        }
        final cards = raw.map((v) => GameStateCodec.cardFromJson(Map<String, dynamic>.from(v as Map))).toList();
        final sourceValue = action['source'];
        if (sourceValue != 'drawPile' && sourceValue != 'previousPlayerDiscard') {
          throw StateError('Unknown draw source.');
        }
        final source = sourceValue == 'previousPlayerDiscard' ? DrawSource.previousPlayerDiscard : DrawSource.drawPile;
        final turn = widget.engine.discardAndDraw(state: _state, playerId: playerId, cardsToDiscard: cards, drawSource: source);
        _state = turn.state;
        _result = turn.roundResult;
      } else {
        throw StateError('Unknown action type.');
      }
      _selected.clear();
      if (action['type'] == 'discard') {
        unawaited(ScottAudio.instance.play('card_discard'));
        unawaited(ScottAudio.instance.play(action['source'] == 'previousPlayerDiscard' ? 'previous_pickup' : 'card_draw'));
      }
      _playRoundSounds();
      _announce(playerId, actionType: action['type'] as String? ?? 'discard', discardedCount: (action['cards'] as List? ?? const []).length, source: action['source'] == 'previousPlayerDiscard' ? DrawSource.previousPlayerDiscard : DrawSource.drawPile);
      _recordRound();
      unawaited(_publish());
      setState(() {});
    } catch (_) {
      widget.sendToPlayer(playerId, {'type': 'actionError', 'message': 'यह चाल मान्य नहीं है। फिर से प्रयास करें।'});
    }
  }

  void _announce(String playerId, {required String actionType, int discardedCount = 0, DrawSource source = DrawSource.drawPile}) {
    // Commentary is reserved for meaningful round outcomes, never routine turns.
    final result = _result;
    if (result == null) return;
    late final String category;
    late final String name;
    if (result.winnerId != null) {
      category = 'winner';
      name = _state.playerById(result.winnerId!)?.name ?? 'खिलाड़ी';
    } else if (result.eliminatedPlayerIds.isNotEmpty) {
      category = 'elimination';
      name = _state.playerById(result.eliminatedPlayerIds.first)?.name ?? 'खिलाड़ी';
    } else if (result.wasAutomatic) {
      category = 'automatic_show';
      name = _state.playerById(result.callerId)?.name ?? 'खिलाड़ी';
    } else if (!result.wasSuccessful) {
      category = 'failed_show';
      name = _state.playerById(result.callerId)?.name ?? 'खिलाड़ी';
    } else if (result.pointsAdded.values.any((value) => value >= 25)) {
      category = 'high_points';
      final hitPlayerId = result.pointsAdded.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      name = _state.playerById(hitPlayerId)?.name ?? 'खिलाड़ी';
    } else {
      return;
    }
    _commentaryText = _commentary.next(category, name);
    _commentaryTimer?.cancel();
    _commentaryTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _commentaryText = null);
      unawaited(_publish());
    });
  }

  void _playRoundSounds() {
    final result = _result;
    if (result == null) return;
    unawaited(ScottAudio.instance.play(result.wasSuccessful ? 'show' : 'failed_show'));
    if (result.eliminatedPlayerIds.isNotEmpty) unawaited(ScottAudio.instance.play('elimination'));
    if (result.winnerId != null) { unawaited(ScottAudio.instance.play('winner')); _confetti.play(); }
  }

  void _show() {
    try {
      final turn = widget.engine.show(_state, widget.hostId);
      setState(() { _state = turn.state; _result = turn.roundResult; _selected.clear(); });
      _playRoundSounds();
      _announce(widget.hostId, actionType: 'show');
      _recordRound();
      unawaited(_publish());
    } catch (e) { _message(e.toString()); }
  }

  void _discard(DrawSource source) {
    final discardedCount = _selected.length;
    try {
      unawaited(ScottAudio.instance.play('card_discard'));
      unawaited(ScottAudio.instance.play(source == DrawSource.drawPile ? 'card_draw' : 'previous_pickup'));
      final turn = widget.engine.discardAndDraw(state: _state, playerId: widget.hostId, cardsToDiscard: _selected.toList(), drawSource: source);
      setState(() { _state = turn.state; _result = turn.roundResult; _selected.clear(); });
      _playRoundSounds();
      _announce(widget.hostId, actionType: 'discard', discardedCount: discardedCount, source: source);
      _recordRound();
      unawaited(_publish());
    } catch (e) { _message(e.toString()); }
  }

  void _nextRound() {
    final caller = _result?.callerId;
    unawaited(ScottAudio.instance.play('shuffle'));
    final next = widget.engine.startNextRound(_state, starterId: caller);
    setState(() { _state = next; _result = null; _selected.clear(); });
    unawaited(_publish());
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final current = _state.currentPlayer;
    final isMyTurn = current.id == widget.hostId && _state.phase == GamePhase.waitingForTurn;
    final isFinished = _state.phase == GamePhase.gameComplete;
    return Scaffold(
      appBar: AppBar(title: Text(isFinished ? 'विजेता' : 'SCOTT • राउंड ${_state.roundNumber}'), actions: [
        IconButton(tooltip: 'खेल के नियम / How to Play', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage())), icon: const Icon(Icons.menu_book_outlined)),
        IconButton(tooltip: 'Scoreboard', onPressed: _scoreboard, icon: const Icon(Icons.leaderboard_outlined)),
      ]),
      body: SafeArea(child: Column(children: [
        _scoreStrip(),
        if (_commentaryText != null) _commentaryBanner(_commentaryText!),
        Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
          if (isFinished) _winnerPanel() else if (_state.phase == GamePhase.roundComplete) _roundResultPanel() else _turnBanner(current.name, isMyTurn),
          const SizedBox(height: 12),
          _opponents(),
          const SizedBox(height: 16),
          _tablePiles(),
          if (_state.discardPile.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('खुले फेंके गए पत्ते', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 5, runSpacing: 5, children: _state.discardPile.map((card) => Text(card.toString(), style: TextStyle(fontWeight: FontWeight.w700, color: card.suit.isRed ? Colors.red : Colors.black87))).toList()),
          ],
          const SizedBox(height: 16),
          const Text('आपके पत्ते', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final card in _state.playerById(widget.hostId)!.hand)
              _PlayingCardTile(card: card, selected: _selected.contains(card), enabled: isMyTurn && card.rank != CardRank.nine, onTap: () => setState(() {
                if (_selected.contains(card)) { _selected.remove(card); } else {
                  if (_selected.isEmpty || _selected.every((c) => c.rank == card.rank)) {
                    _selected.add(card);
                  } else {
                    _message('एक साथ केवल एक ही रैंक के पत्ते फेंक सकते हैं।');
                  }
                }
              })),
          ]),
          const SizedBox(height: 12),
          if (isMyTurn) _turnControls(),
        ])),
      ])),
    );
  }

  Widget _commentaryBanner(String message) => Container(
    margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFFFD166), Color(0xFFFF8C42)]),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x33222222), blurRadius: 8, offset: Offset(0, 3))],
    ),
    child: Row(children: [
      const Icon(Icons.campaign_rounded, size: 30, color: Color(0xFF542900)),
      const SizedBox(width: 12),
      Expanded(child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w900, color: Color(0xFF542900)))),
    ]),
  );

  Widget _scoreStrip() => Container(
    width: double.infinity,
    color: const Color(0xFFE6F0F2),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'लक्ष्य: ${_state.targetScore} अंक  •  ${_state.players.where((p) => !p.isEliminated).length} खिलाड़ी बाकी',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final player in _state.players)
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 90, maxWidth: 150), child: Chip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: player.isEliminated ? const Color(0xFFFFDCDC) : Colors.white,
              label: Text('${player.name}: ${player.score}${player.isEliminated ? ' • OUT' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            )),
        ]),
      ],
    ),
  );

  Widget _turnBanner(String name, bool myTurn) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: myTurn ? const Color(0xFFE0F4EF) : const Color(0xFFFFF3DB), borderRadius: BorderRadius.circular(14)),
    child: Text(myTurn ? 'आपकी बारी है — SHOW करें या पत्ते बदलें।' : '$name की बारी है।', style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _opponents() => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      for (final p in _state.players)
        Container(
          width: 145, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.isEliminated ? const Color(0xFFFFE6E6) : p.id == _state.currentPlayer.id && _state.phase == GamePhase.waitingForTurn ? const Color(0xFFE0F4EF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.id == _state.currentPlayer.id && _state.phase == GamePhase.waitingForTurn ? const Color(0xFF16A6A1) : const Color(0xFFE0E7EC), width: p.id == _state.currentPlayer.id && _state.phase == GamePhase.waitingForTurn ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('स्कोर: ${p.score}', style: const TextStyle(fontSize: 12)),
            if (p.isEliminated) const Text('ससम्मान बाहेर 😂', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w800)),
            if (_state.phase == GamePhase.waitingForTurn)
              Row(children: List.generate(p.hand.length, (_) => const Padding(padding: EdgeInsets.only(right: 2), child: _CardBack())))
            else
              Wrap(spacing: 3, children: p.hand.map((card) => Text(card.toString(), style: TextStyle(fontSize: 11, color: card.suit.isRed ? Colors.red : Colors.black87))).toList()),
            if (_state.phase != GamePhase.waitingForTurn) Text('हाथ का जोड़: ${p.handTotal}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
    ],
  );

  Widget _tablePiles() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    Column(children: [
      const Text('DRAW PILE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Container(width: 58, height: 82, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF183D5A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 2)), child: Text('${_state.drawPile.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))),
    ]),
    Column(children: [
      const Text('DISCARD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (_state.discardPile.isEmpty) Container(width: 58, height: 82, decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)))
      else SizedBox(width: 112, height: 90, child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < _state.lastDiscardGroup.length; i++)
          Positioned(left: i * 20.0, top: i.isEven ? 0 : 5, child: _PlayingCardTile(card: _state.lastDiscardGroup[i], selected: false, enabled: false, onTap: () {})),
      ])),
    ]),
  ]);

  Widget _turnControls() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    FilledButton(onPressed: _selected.isEmpty ? null : () => _discard(DrawSource.drawPile), child: Text('चुने पत्ते फेंकें + Draw Pile से 1 लें (${_selected.length})')),
    OutlinedButton(onPressed: _selected.isEmpty || _state.lastDiscardGroup.isEmpty ? null : () => _discard(DrawSource.previousPlayerDiscard), child: const Text('पत्ते फेंकें + पिछले खिलाड़ी का पत्ता लें')),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: _show, icon: const Icon(Icons.visibility), label: const Text('SHOW')),
  ]);

  Widget _roundResultPanel() => Card(color: _result?.wasSuccessful == true ? const Color(0xFFEAF5EE) : const Color(0xFFFFE9EC), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('कॉलर ${_state.playerById(_result?.callerId ?? '')?.name ?? '—'} — ${_result?.wasSuccessful == true ? 'SHOW सफल!' : 'SHOW असफल!'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
    const SizedBox(height: 8),
    for (final p in _state.players)
      Text('${p.name}: हाथ ${p.handTotal} • इस राउंड +${_result?.pointsAdded[p.id] ?? 0} • कुल ${p.score}${p.isEliminated ? ' • ससम्मान बाहेर 😂' : ''}'),
    const SizedBox(height: 12),
    if (!isWinner) FilledButton(onPressed: _nextRound, child: const Text('अगला राउंड शुरू करें')),
  ])));

  bool get isWinner => _state.phase == GamePhase.gameComplete;

  Widget _winnerPanel() {
    final winner = _state.playerById(_state.winnerId ?? '');
    return Stack(alignment: Alignment.topCenter, children: [
      ConfettiWidget(confettiController: _confetti, blastDirectionality: BlastDirectionality.explosive, shouldLoop: false, numberOfParticles: 35, maxBlastForce: 24, minBlastForce: 8),
      Card(color: const Color(0xFFFFF0C9), child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
      const Icon(Icons.emoji_events, size: 64, color: Color(0xFFB57B11)),
      const Text('SCOTT CHAMPION', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(winner?.name ?? 'विजेता', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    ])))]);
  }

  void _scoreboard() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('Scoreboard', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            for (final player in _state.players)
              ListTile(
                title: Text(player.name),
                subtitle: player.isEliminated ? const Text('ससम्मान बाहेर 😂') : null,
                trailing: Text('${player.score} / ${_state.targetScore}', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            const Divider(),
            const Text('Round-by-round history', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            for (final entry in _history)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Round ${entry['round']} • ${entry['successful'] == true ? 'Successful' : 'Failed'} SHOW${entry['automatic'] == true ? ' • Automatic' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('Caller: ${_state.playerById(entry['callerId'] as String)?.name ?? '—'}'),
                      Text('हाथ का जोड़: ${(entry['handTotals'] as Map).entries.map((e) => '${_state.playerById(e.key.toString())?.name ?? e.key}: ${e.value}').join(' • ')}'),
                      Text('अंक मिले: ${(entry['pointsAdded'] as Map).entries.map((e) => '${_state.playerById(e.key.toString())?.name ?? e.key}: +${e.value}').join(' • ')}'),
                      Text('कुल स्कोर: ${(entry['scores'] as Map).entries.map((e) => '${_state.playerById(e.key.toString())?.name ?? e.key}: ${e.value}').join(' • ')}'),
                      if ((entry['eliminatedPlayerIds'] as List? ?? const []).isNotEmpty)
                        Text(
                          'ससम्मान बाहेर 😂: ${(entry['eliminatedPlayerIds'] as List).map((id) => _state.playerById(id.toString())?.name ?? id).join(', ')}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                        ),
                      if (entry['winnerId'] != null)
                        Text('विजेता: ${_state.playerById(entry['winnerId'] as String)?.name ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RemoteGameTablePage extends StatefulWidget {
  const RemoteGameTablePage({super.key, required this.messages, required this.sendAction, required this.playerId, required this.initialMessage});
  final Stream<Map<String, dynamic>> messages;
  final void Function(Map<String, dynamic>) sendAction;
  final String playerId;
  final Map<String, dynamic> initialMessage;
  @override
  State<RemoteGameTablePage> createState() => _RemoteGameTablePageState();
}

class _RemoteGameTablePageState extends State<RemoteGameTablePage> {
  late Map<String, dynamic> _public;
  late List<PlayingCard> _hand;
  final Set<PlayingCard> _selected = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _message;
  String? _lastSnapshotFingerprint;
  Timer? _commentaryTimer;
  String? _lastCommentary;

  @override
  void initState() {
    super.initState();
    _apply(widget.initialMessage);
    _sub = widget.messages.listen((message) {
      if (!mounted) return;
      if (message['type'] == 'game') {
        // Shared outcome commentary is rendered in the large in-game banner,
        // not as a repetitive SnackBar on every polling update.
        setState(() => _apply(message));
      }
      if (message['type'] == 'actionError') setState(() => _message = message['message'] as String?);
    });
  }

  void _apply(Map<String, dynamic> message) {
    final nextPublic = Map<String, dynamic>.from(message['state'] as Map);
    final nextHand = (message['privateHand'] as List? ?? const [])
        .map((v) => GameStateCodec.cardFromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    // Online and local clients poll periodically. Keep selection while the
    // authoritative snapshot is unchanged; otherwise every poll cancels it.
    final fingerprint = jsonEncode([nextPublic, nextHand.map(GameStateCodec.cardToJson).toList()]);
    if (_lastSnapshotFingerprint != fingerprint) {
      _selected.clear();
      _lastSnapshotFingerprint = fingerprint;
    }
    _public = nextPublic;
    _hand = nextHand;
    final commentary = nextPublic['commentary'] as String?;
    if (commentary != _lastCommentary) {
      _lastCommentary = commentary;
      _commentaryTimer?.cancel();
      if (commentary != null && commentary.isNotEmpty) {
        _commentaryTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && _lastCommentary == commentary) setState(() => _lastCommentary = null);
        });
      }
    }
  }

  @override
  void dispose() { unawaited(_sub?.cancel()); _commentaryTimer?.cancel(); super.dispose(); }

  Widget _remoteRoundResultPanel(List<Map> players) {
    final result = Map<String, dynamic>.from((_public['roundResult'] as Map?) ?? const {});
    final callerId = result['callerId']?.toString();
    final caller = players.where((p) => p['id']?.toString() == callerId).toList();
    final successful = result['successful'] == true;
    final totals = Map<String, dynamic>.from((result['handTotals'] as Map?) ?? const {});
    final added = Map<String, dynamic>.from((result['pointsAdded'] as Map?) ?? const {});
    return Card(
      color: successful ? const Color(0xFFEAF5EE) : const Color(0xFFFFE9EC),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('कॉलर ${caller.isEmpty ? '—' : caller.first['name']} — SHOW ${successful ? 'सफल!' : 'असफल!'}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
          const SizedBox(height: 8),
          for (final p in players)
            Text('${p['name']}: हाथ ${totals[p['id']?.toString()] ?? p['handTotal'] ?? 0} • इस राउंड +${added[p['id']?.toString()] ?? 0} • कुल ${p['score']}'),
          const SizedBox(height: 8),
          const Text('अगले राउंड के लिए Host की प्रतीक्षा करें।', style: TextStyle(color: Color(0xFF52616B), fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  void _scoreboard() {
    final players = (_public['players'] as List).cast<Map>();
    final names = {for (final player in players) player['id'].toString(): player['name'].toString()};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('Scoreboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            for (final player in players)
              ListTile(
                title: Text('${player['name']}'),
                subtitle: player['isEliminated'] == true ? const Text('ससम्मान बाहेर 😂') : null,
                trailing: Text('${player['score']} / ${_public['targetScore']}'),
              ),
            const Divider(),
            const Text('Round History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            for (final entry in (_public['history'] as List? ?? const []))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Round ${entry['round']} • ${entry['successful'] == true ? 'Successful' : 'Failed'} SHOW${entry['automatic'] == true ? ' • Automatic' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('Caller: ${names[entry['callerId']?.toString()] ?? '—'}'),
                      Text('हाथ का जोड़: ${(entry['handTotals'] as Map).entries.map((e) => '${names[e.key.toString()] ?? e.key}: ${e.value}').join(' • ')}'),
                      Text('अंक मिले: ${(entry['pointsAdded'] as Map).entries.map((e) => '${names[e.key.toString()] ?? e.key}: +${e.value}').join(' • ')}'),
                      Text('कुल स्कोर: ${(entry['scores'] as Map).entries.map((e) => '${names[e.key.toString()] ?? e.key}: ${e.value}').join(' • ')}'),
                      if ((entry['eliminatedPlayerIds'] as List? ?? const []).isNotEmpty)
                        Text(
                          'ससम्मान बाहेर 😂: ${(entry['eliminatedPlayerIds'] as List).map((id) => names[id.toString()] ?? id).join(', ')}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                        ),
                      if (entry['winnerId'] != null)
                        Text('विजेता: ${names[entry['winnerId'].toString()] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = (_public['players'] as List).cast<Map>();
    final me = widget.playerId;
    final currentId = _public['currentPlayerId'];
    final myTurn = currentId == me && _public['phase'] == GamePhase.waitingForTurn.name;
    final reveal = _public['revealHands'] == true;
    final phase = _public['phase'];
    final winner = _public['winnerId'];
    final canTakePrevious = (_public['lastDiscardGroup'] as List? ?? const []).isNotEmpty;
    final matches = players.cast<Map>().where((p) => p['id'] == me).toList();
    final myPlayer = matches.isEmpty ? null : matches.first;
    final currentPlayer = players.cast<Map>().firstWhere((p) => p['id'] == currentId, orElse: () => players.first);
    return Scaffold(
      appBar: AppBar(
        title: Text(phase == GamePhase.gameComplete.name ? 'विजेता' : 'SCOTT • राउंड ${_public['roundNumber']}'),
        actions: [
          IconButton(tooltip: 'खेल के नियम / How to Play', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScottRulesPage())), icon: const Icon(Icons.menu_book_outlined)),
          IconButton(tooltip: 'Scoreboard', onPressed: _scoreboard, icon: const Icon(Icons.leaderboard_outlined)),
        ],
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(color: Color(0xFFE6F0F2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('लक्ष्य: ${_public['targetScore']} अंक  •  ${players.where((p) => p['isEliminated'] != true).length} खिलाड़ी बाकी', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final p in players)
                Chip(visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: p['isEliminated'] == true ? const Color(0xFFFFDCDC) : Colors.white,
                  label: Text('${p['name']}: ${p['score']}${p['isEliminated'] == true ? ' • OUT' : ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        if (phase == GamePhase.waitingForTurn.name)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: myTurn ? const Color(0xFFE0F4EF) : const Color(0xFFFFF3DB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              myTurn ? 'आपकी बारी है — SHOW करें या पत्ते बदलें।' : '${currentPlayer['name']} की बारी है।',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        if (phase == GamePhase.roundComplete.name) _remoteRoundResultPanel(players),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in players)
            Container(
              width: 145, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p['isEliminated'] == true ? const Color(0xFFFFE6E6)
                    : (p['id'] == currentId && phase == GamePhase.waitingForTurn.name) ? const Color(0xFFE0F4EF) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: p['id'] == currentId && phase == GamePhase.waitingForTurn.name ? const Color(0xFF16A6A1) : const Color(0xFFE0E7EC),
                  width: p['id'] == currentId && phase == GamePhase.waitingForTurn.name ? 2 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('स्कोर: ${p['score']}', style: const TextStyle(fontSize: 12)),
                if (p['isEliminated'] == true) const Text('ससम्मान बाहेर 😂', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w800)),
                if (reveal) ...[
                  Text('हाथ का जोड़: ${p['handTotal']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(spacing: 3, runSpacing: 2, children: (p['hand'] as List? ?? const []).map((raw) {
                    final card = GameStateCodec.cardFromJson(Map<String, dynamic>.from(raw as Map));
                    return Text(card.toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: card.suit.isRed ? Colors.red : Colors.black87));
                  }).toList()),
                ] else
                  Row(children: List.generate(p['handCount'] as int? ?? 0, (_) => const Padding(padding: EdgeInsets.only(right: 2), child: _CardBack()))),
              ]),
            ),
        ]),
        if (_lastCommentary != null && _lastCommentary!.isNotEmpty)
          _sharedCommentaryBanner(_lastCommentary!),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(children: [
              const Text('DRAW PILE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                width: 76, height: 104, alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFF183D5A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))]),
                child: Text('${_public['drawPileCount']}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
              ),
            ]),
            Column(children: [
              const Text('DISCARD', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              if ((_public['discardPile'] as List? ?? const []).isEmpty)
                Container(width: 76, height: 104, decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)))
              else
                SizedBox(width: 132, height: 110, child: Stack(clipBehavior: Clip.none, children: [
                  for (var i = 0; i < (_public['lastDiscardGroup'] as List? ?? const []).length; i++)
                    Positioned(left: i * 20.0, top: i.isEven ? 0 : 5, child: _PlayingCardTile(card: GameStateCodec.cardFromJson(Map<String, dynamic>.from((_public['lastDiscardGroup'] as List)[i] as Map)), selected: false, enabled: false, onTap: () {})),
                ])),
            ]),
          ],
        ),
        const SizedBox(height: 14),
        if ((_public['discardPile'] as List? ?? const []).isNotEmpty) ...[
          const Text('खुले फेंके गए पत्ते', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 6, children: (_public['discardPile'] as List).map((v) { final card = GameStateCodec.cardFromJson(Map<String, dynamic>.from(v as Map)); return Text(card.toString(), style: TextStyle(color: card.suit.isRed ? Colors.red : Colors.black87, fontWeight: FontWeight.w700)); }).toList()),
        ],
        if (phase == GamePhase.roundComplete.name) const Text('राउंड पूरा हुआ। अगले राउंड के लिए Host की प्रतीक्षा करें।'),
        if (winner != null) Text('विजेता: ${players.firstWhere((p) => p['id'] == winner)['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        const Text('आपके पत्ते', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 8, children: [
          for (final card in _hand)
            _PlayingCardTile(card: card, selected: _selected.contains(card), enabled: myTurn && card.rank != CardRank.nine, onTap: () => setState(() {
              if (_selected.contains(card)) {
                _selected.remove(card);
              } else if (_selected.isEmpty || _selected.every((c) => c.rank == card.rank)) {
                _selected.add(card);
              } else {
                _message = 'एक ही रैंक के पत्ते साथ चुनें।';
              }
            })),
        ]),
        if (myTurn) ...[
          FilledButton(onPressed: _selected.isEmpty ? null : () {
            unawaited(ScottAudio.instance.play('card_discard'));
            unawaited(ScottAudio.instance.play('card_draw'));
            widget.sendAction({'type': 'discard', 'cards': _selected.map(GameStateCodec.cardToJson).toList(), 'source': 'drawPile'});
          }, child: const Text('चुने पत्ते फेंकें + Draw Pile से 1 लें')),
          OutlinedButton(onPressed: _selected.isEmpty || !canTakePrevious ? null : () {
            unawaited(ScottAudio.instance.play('card_discard'));
            unawaited(ScottAudio.instance.play('previous_pickup'));
            widget.sendAction({'type': 'discard', 'cards': _selected.map(GameStateCodec.cardToJson).toList(), 'source': 'previousPlayerDiscard'});
          }, child: const Text('पत्ते फेंकें + पिछले खिलाड़ी का पत्ता लें')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () { unawaited(ScottAudio.instance.play('show')); widget.sendAction({'type': 'show'}); }, icon: const Icon(Icons.visibility), label: const Text('SHOW')),
        ],
        if (_message != null) Text(_message!, style: const TextStyle(color: Colors.red)),
        if (myPlayer == null) const Text('इस कमरे में आपका खिलाड़ी ID नहीं मिला.'),
        OutlinedButton.icon(onPressed: _scoreboard, icon: const Icon(Icons.leaderboard), label: const Text('Scoreboard और History')),
      ])),
    );
  }
}

Widget _sharedCommentaryBanner(String message) => Container(
  margin: const EdgeInsets.symmetric(vertical: 12),
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  decoration: BoxDecoration(
    gradient: const LinearGradient(colors: [Color(0xFFFFD166), Color(0xFFFF8C42)]),
    borderRadius: BorderRadius.circular(18),
    boxShadow: const [BoxShadow(color: Color(0x33222222), blurRadius: 8, offset: Offset(0, 3))],
  ),
  child: Row(children: [
    const Icon(Icons.campaign_rounded, size: 30, color: Color(0xFF542900)),
    const SizedBox(width: 12),
    Expanded(child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w900, color: Color(0xFF542900)))),
  ]),
);

class _PlayingCardTile extends StatelessWidget {
  const _PlayingCardTile({required this.card, required this.selected, required this.enabled, required this.onTap});
  final PlayingCard card;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final red = card.suit.isRed;
    return GestureDetector(
      onTap: enabled ? () { unawaited(ScottAudio.instance.play('tap')); onTap(); } : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 58, height: 82,
        transform: Matrix4.translationValues(0, selected ? -7 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF16A6A1) : const Color(0xFFD7DEE4), width: selected ? 2.5 : 1),
          boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(card.rank.shortLabel, style: TextStyle(color: red ? Colors.red : const Color(0xFF18232D), fontSize: 21, fontWeight: FontWeight.w900)),
          Text(card.suit.symbol, style: TextStyle(color: red ? Colors.red : const Color(0xFF18232D), fontSize: 23)),
          Text('${card.value}', style: const TextStyle(fontSize: 10, color: Color(0xFF687987))),
        ]),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack();
  @override
  Widget build(BuildContext context) => Container(
    width: 14, height: 22,
    decoration: BoxDecoration(color: const Color(0xFF244D6B), borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white, width: 1)),
  );
}
