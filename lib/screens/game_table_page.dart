import 'dart:async';
import 'package:flutter/material.dart';
import '../game/game_models.dart';
import '../game/playing_card.dart';
import '../game/scott_game_engine.dart';
import '../network/game_state_codec.dart';
import '../services/scott_audio.dart';
import '../game/commentary.dart';
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
  String? _commentaryText;
  StreamSubscription<({String playerId, Map<String, dynamic> action})>? _actionsSub;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    unawaited(_publish());
    _actionsSub = widget.actions.listen((event) => _handleRemoteAction(event.playerId, event.action));
  }

  @override
  void dispose() {
    unawaited(_actionsSub?.cancel());
    super.dispose();
  }

  Future<void> _publish() {
    final publicState = GameStateCodec.publicState(_state, revealHands: _state.phase != GamePhase.waitingForTurn);
    publicState['history'] = List<Map<String, dynamic>>.from(_history);
    publicState['commentary'] = _commentaryText;
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
    });
  }

  void _handleRemoteAction(String playerId, Map<String, dynamic> action) {
    if (!mounted || _state.phase != GamePhase.waitingForTurn || _state.currentPlayer.id != playerId) return;
    try {
      if (action['type'] == 'show') {
        final turn = widget.engine.show(_state, playerId);
        _state = turn.state;
        _result = turn.roundResult;
      } else if (action['type'] == 'discard') {
        final raw = action['cards'] as List? ?? const [];
        final cards = raw.map((v) => GameStateCodec.cardFromJson(Map<String, dynamic>.from(v as Map))).toList();
        final source = action['source'] == 'previousPlayerDiscard' ? DrawSource.previousPlayerDiscard : DrawSource.drawPile;
        final turn = widget.engine.discardAndDraw(state: _state, playerId: playerId, cardsToDiscard: cards, drawSource: source);
        _state = turn.state;
        _result = turn.roundResult;
      }
      _selected.clear();
      _playRoundSounds();
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
    final name = _state.playerById(playerId)?.name ?? 'खिलाड़ी';
    String category;
    if (_result != null) {
      if (_result!.winnerId != null) {
        category = 'winner';
      } else if (_result!.eliminatedPlayerIds.isNotEmpty) {
        category = 'elimination';
      } else if (_result!.wasAutomatic) {
        category = 'automatic_show';
      } else if (!_result!.wasSuccessful) {
        category = 'failed_show';
      } else if (_result!.pointsAdded.values.any((value) => value >= 25)) {
        category = 'high_points';
      } else {
        category = 'smart_move';
      }
    } else if (actionType == 'show') {
      category = 'smart_move';
    } else if (source == DrawSource.previousPlayerDiscard) {
      category = 'previous_pickup';
    } else if (discardedCount >= 3) {
      category = 'triple_quad';
    } else if (discardedCount == 2) {
      category = 'pair_discard';
    } else {
      category = 'smart_move';
    }
    _commentaryText = _commentary.next(category, name);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_commentaryText!),
      duration: const Duration(milliseconds: 4600),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _playRoundSounds() {
    final result = _result;
    if (result == null) return;
    unawaited(ScottAudio.instance.play(result.wasSuccessful ? 'show' : 'failed_show'));
    if (result.eliminatedPlayerIds.isNotEmpty) unawaited(ScottAudio.instance.play('elimination'));
    if (result.winnerId != null) unawaited(ScottAudio.instance.play('winner'));
  }

  void _show() {
    try {
      unawaited(ScottAudio.instance.play('show'));
      final turn = widget.engine.show(_state, widget.hostId);
      setState(() { _state = turn.state; _result = turn.roundResult; _selected.clear(); });
      _announce(widget.hostId, actionType: 'show');
      _recordRound();
      unawaited(_publish());
    } catch (e) { _message(e.toString()); }
  }

  void _discard(DrawSource source) {
    try {
      unawaited(ScottAudio.instance.play('card_discard'));
      unawaited(ScottAudio.instance.play(source == DrawSource.drawPile ? 'card_draw' : 'previous_pickup'));
      final turn = widget.engine.discardAndDraw(state: _state, playerId: widget.hostId, cardsToDiscard: _selected.toList(), drawSource: source);
      setState(() { _state = turn.state; _result = turn.roundResult; _selected.clear(); });
      _announce(widget.hostId, actionType: 'discard', discardedCount: _result == null ? _selected.length : 0, source: source);
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
        IconButton(tooltip: 'Scoreboard', onPressed: _scoreboard, icon: const Icon(Icons.leaderboard_outlined)),
      ]),
      body: SafeArea(child: Column(children: [
        _scoreStrip(),
        Expanded(child: ListView(padding: const EdgeInsets.all(14), children: [
          if (isFinished) _winnerPanel() else if (_state.phase == GamePhase.roundComplete) _roundResultPanel() else _turnBanner(current.name, isMyTurn),
          const SizedBox(height: 12),
          _opponents(),
          const SizedBox(height: 16),
          _tablePiles(),
          const SizedBox(height: 16),
          const Text('आपके पत्ते', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final card in _state.playerById(widget.hostId)!.hand)
              _PlayingCardTile(card: card, selected: _selected.contains(card), enabled: isMyTurn && card.rank != CardRank.nine, onTap: () => setState(() {
                if (_selected.contains(card)) { _selected.remove(card); } else {
                  if (_selected.isEmpty || _selected.every((c) => c.rank == card.rank)) _selected.add(card);
                  else _message('एक साथ केवल एक ही रैंक के पत्ते फेंक सकते हैं।');
                }
              })),
          ]),
          const SizedBox(height: 12),
          if (isMyTurn) _turnControls(),
        ])),
      ])),
    );
  }

  Widget _scoreStrip() => Container(
    width: double.infinity, color: const Color(0xFFE6F0F2),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Text('लक्ष्य: ${_state.targetScore} अंक    •    खिलाड़ी: ${_state.players.where((p) => !p.isEliminated).length} बाकी', style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _turnBanner(String name, bool myTurn) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: myTurn ? const Color(0xFFE0F4EF) : const Color(0xFFFFF3DB), borderRadius: BorderRadius.circular(14)),
    child: Text(myTurn ? 'आपकी बारी है — SHOW करें या पत्ते बदलें।' : '$name की बारी है।', style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _opponents() => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      for (final p in _state.players.where((p) => p.id != widget.hostId))
        Container(
          width: 145, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.isEliminated ? const Color(0xFFFFE6E6) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7EC))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('स्कोर: ${p.score}', style: const TextStyle(fontSize: 12)),
            if (p.isEliminated) const Text('ससम्मान बाहेर 😂', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w800))
            else Row(children: List.generate(p.hand.length, (_) => const Padding(padding: EdgeInsets.only(right: 2), child: _CardBack()))),
            if (_state.phase != GamePhase.waitingForTurn) Text('हाथ: ${p.handTotal}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
      else _PlayingCardTile(card: _state.discardPile.last, selected: false, enabled: false, onTap: () {}),
    ]),
  ]);

  Widget _turnControls() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    OutlinedButton.icon(onPressed: _show, icon: const Icon(Icons.visibility), label: const Text('SHOW')),
    const SizedBox(height: 8),
    FilledButton(onPressed: _selected.isEmpty ? null : () => _discard(DrawSource.drawPile), child: Text('चुने पत्ते फेंकें + Draw Pile से 1 लें (${_selected.length})')),
    OutlinedButton(onPressed: _selected.isEmpty || _state.lastDiscardGroup.isEmpty ? null : () => _discard(DrawSource.previousPlayerDiscard), child: const Text('पत्ते फेंकें + पिछले खिलाड़ी का पत्ता लें')),
  ]);

  Widget _roundResultPanel() => Card(color: const Color(0xFFEAF5EE), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(_result?.wasSuccessful == true ? 'SHOW सफल!' : 'SHOW असफल!', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
    const SizedBox(height: 8),
    for (final p in _state.players)
      Text('${p.name}: हाथ ${p.handTotal} • इस राउंड +${_result?.pointsAdded[p.id] ?? 0} • कुल ${p.score}${p.isEliminated ? ' • ससम्मान बाहेर 😂' : ''}'),
    const SizedBox(height: 12),
    if (!isWinner) FilledButton(onPressed: _nextRound, child: const Text('अगला राउंड शुरू करें')),
  ])));

  bool get isWinner => _state.phase == GamePhase.gameComplete;

  Widget _winnerPanel() {
    final winner = _state.playerById(_state.winnerId ?? '');
    return Card(color: const Color(0xFFFFF0C9), child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
      const Icon(Icons.emoji_events, size: 64, color: Color(0xFFB57B11)),
      const Text('SCOTT CHAMPION', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(winner?.name ?? 'विजेता', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
    ])));
  }

  void _scoreboard() { showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Scoreboard', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
    for (final p in _state.players) ListTile(title: Text(p.name), subtitle: p.isEliminated ? const Text('ससम्मान बाहेर 😂') : null, trailing: Text('${p.score} / ${_state.targetScore}', style: const TextStyle(fontWeight: FontWeight.w900))),
    const Divider(),
    const Text('Round-by-round history', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
    for (final entry in _history)
      ListTile(
        title: Text('Round ${entry['round']} • ${entry['successful'] == true ? 'Successful SHOW' : 'Failed SHOW'}'),
        subtitle: Text('Caller: ${_state.playerById(entry['callerId'] as String)?.name ?? '—'}${entry['automatic'] == true ? ' • Automatic' : ''}'),
        trailing: Text((entry['pointsAdded'] as Map).entries.map((e) => '${_state.playerById(e.key.toString())?.name ?? e.key}: +${e.value}').join(' | '), style: const TextStyle(fontSize: 10)),
      ),
  ]))); }
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
  String? _lastCommentary;

  @override
  void initState() {
    super.initState();
    _apply(widget.initialMessage);
    _sub = widget.messages.listen((message) {
      if (message['type'] == 'game') {
        final incoming = message['state'] is Map ? (message['state'] as Map)['commentary'] as String? : null;
        if (incoming != null && incoming != _lastCommentary) {
          _lastCommentary = incoming;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(incoming), duration: const Duration(milliseconds: 4600), behavior: SnackBarBehavior.floating));
        }
        setState(() => _apply(message));
      }
      if (message['type'] == 'actionError') setState(() => _message = message['message'] as String?);
    });
  }

  void _apply(Map<String, dynamic> message) {
    _public = Map<String, dynamic>.from(message['state'] as Map);
    _hand = (message['privateHand'] as List? ?? const []).map((v) => GameStateCodec.cardFromJson(Map<String, dynamic>.from(v as Map))).toList();
    _selected.clear();
  }

  @override
  void dispose() { unawaited(_sub?.cancel()); super.dispose(); }

  void _scoreboard() => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Scoreboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    for (final p in (_public['players'] as List).cast<Map>()) ListTile(title: Text('${p['name']}'), trailing: Text('${p['score']} / ${_public['targetScore']}')),
    const Divider(),
    const Text('Round History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
    for (final entry in (_public['history'] as List? ?? const [])) ListTile(title: Text('Round ${entry['round']} • ${entry['successful'] == true ? 'Successful' : 'Failed'} SHOW'), subtitle: Text('Points: ${(entry['pointsAdded'] as Map).entries.map((e) => '${e.key}: +${e.value}').join(' | ')}')),
  ])));

  @override
  Widget build(BuildContext context) {
    final players = (_public['players'] as List).cast<Map>();
    final me = widget.playerId;
    final currentId = _public['currentPlayerId'];
    final myTurn = currentId == me && _public['phase'] == GamePhase.waitingForTurn.name;
    final reveal = _public['revealHands'] == true;
    final phase = _public['phase'];
    final winner = _public['winnerId'];
    final matches = players.cast<Map>().where((p) => p['id'] == me).toList();
    final myPlayer = matches.isEmpty ? null : matches.first;
    return Scaffold(
      appBar: AppBar(title: Text(phase == GamePhase.gameComplete.name ? 'विजेता' : 'SCOTT • राउंड ${_public['roundNumber']}')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(14), children: [
        Text('लक्ष्य: ${_public['targetScore']} • Draw pile: ${_public['drawPileCount']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (final p in players)
          ListTile(
            dense: true,
            title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(p['isEliminated'] == true ? 'ससम्मान बाहेर 😂' : 'स्कोर: ${p['score']}'),
            trailing: reveal ? Text('हाथ: ${p['handTotal']}') : const Text('🂠 🂠 🂠 🂠 🂠'),
          ),
        const SizedBox(height: 12),
        Text(myTurn ? 'आपकी बारी है' : 'अभी ${players.firstWhere((p) => p['id'] == currentId)['name']} की बारी है', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        if (phase == GamePhase.roundComplete.name) const Text('राउंड पूरा हुआ। अगले राउंड के लिए Host की प्रतीक्षा करें।'),
        if (winner != null) Text('विजेता: ${players.firstWhere((p) => p['id'] == winner)['name']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        const Text('आपके पत्ते', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 8, children: [
          for (final card in _hand)
            _PlayingCardTile(card: card, selected: _selected.contains(card), enabled: myTurn && card.rank != CardRank.nine, onTap: () => setState(() {
              if (_selected.contains(card)) _selected.remove(card);
              else if (_selected.isEmpty || _selected.every((c) => c.rank == card.rank)) _selected.add(card);
              else _message = 'एक ही रैंक के पत्ते साथ चुनें।';
            })),
        ]),
        if (myTurn) ...[
          OutlinedButton(onPressed: () => widget.sendAction({'type': 'show'}), child: const Text('SHOW')),
          FilledButton(onPressed: _selected.isEmpty ? null : () {
            widget.sendAction({'type': 'discard', 'cards': _selected.map(GameStateCodec.cardToJson).toList(), 'source': 'drawPile'});
          }, child: const Text('चुने पत्ते फेंकें + Draw Pile से लें')),
          OutlinedButton(onPressed: _selected.isEmpty ? null : () {
            widget.sendAction({'type': 'discard', 'cards': _selected.map(GameStateCodec.cardToJson).toList(), 'source': 'previousPlayerDiscard'});
          }, child: const Text('चुने पत्ते फेंकें + पिछला पत्ता लें')),
        ],
        if (_message != null) Text(_message!, style: const TextStyle(color: Colors.red)),
        if (myPlayer == null) const Text('इस कमरे में आपका खिलाड़ी ID नहीं मिला।'),
      ])),
    );
  }
}

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
      onTap: enabled ? onTap : null,
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
