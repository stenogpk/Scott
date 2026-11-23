import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String _voiceTokenEndpoint = 'https://scott-voice-token.theshartendu.workers.dev';

class VoiceChatPanel extends StatefulWidget {
  const VoiceChatPanel({super.key, required this.roomCode, required this.getFirebaseIdToken});
  final String roomCode;
  final Future<String> Function() getFirebaseIdToken;
  @override
  State<VoiceChatPanel> createState() => _VoiceChatPanelState();
}

class _VoiceChatPanelState extends State<VoiceChatPanel> {
  RtcEngine? _engine;
  bool _joining = false;
  bool _joined = false;
  bool _muted = false;
  String? _error;
  final Set<int> _remoteUsers = <int>{};

  Future<void> _join() async {
    if (_joining || _joined) return;
    setState(() { _joining = true; _error = null; });
    RtcEngine? engine;
    try {
      if (!kIsWeb) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) throw StateError('Voice Chat के लिए Microphone permission जरूरी है।');
      }
      final idToken = await widget.getFirebaseIdToken();
      final response = await http.post(Uri.parse('$_voiceTokenEndpoint/rtc-token'),
        headers: {'content-type': 'application/json', 'authorization': 'Bearer $idToken'},
        body: jsonEncode({'roomCode': widget.roomCode})).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw StateError(body is Map ? (body['error']?.toString() ?? 'Voice token request failed (${response.statusCode}).') : 'Voice token request failed (${response.statusCode}).');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final appId = payload['appId'] as String;
      final channel = payload['channel'] as String;
      final token = payload['token'] as String;
      final uid = (payload['uid'] as num).toInt();
      engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId, channelProfile: ChannelProfileType.channelProfileCommunication));
      await engine.enableAudio();
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) { if (mounted) setState(() { _joined = true; _joining = false; _error = null; }); },
        onUserJoined: (connection, remoteUid, elapsed) { if (mounted) setState(() => _remoteUsers.add(remoteUid)); },
        onUserOffline: (connection, remoteUid, reason) { if (mounted) setState(() => _remoteUsers.remove(remoteUid)); },
        onError: (err, msg) { if (mounted) setState(() => _error = 'Agora error $err: $msg'); },
      ));
      await engine.joinChannel(token: token, channelId: channel, uid: uid, options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster, publishMicrophoneTrack: true, publishCameraTrack: false,
        autoSubscribeAudio: true, autoSubscribeVideo: false));
      _engine = engine;
      if (mounted) setState(() => _joining = false);
    } catch (error) {
      try { await engine?.leaveChannel(); } catch (_) {}
      try { await engine?.release(); } catch (_) {}
      if (mounted) setState(() { _joining = false; _joined = false; _error = error.toString().replaceFirst('Bad state: ', ''); });
    }
  }
  Future<void> _toggleMute() async {
    final next = !_muted;
    try { await _engine?.muteLocalAudioStream(next); if (mounted) setState(() => _muted = next); }
    catch (error) { if (mounted) setState(() => _error = 'Mic setting failed: $error'); }
  }
  Future<void> _leave() async {
    final engine = _engine; _engine = null;
    try { await engine?.leaveChannel(); } catch (_) {}
    try { await engine?.release(); } catch (_) {}
    if (mounted) setState(() { _joined = false; _joining = false; _muted = false; _remoteUsers.clear(); });
  }
  @override
  void dispose() {
    final engine = _engine; _engine = null;
    if (engine != null) unawaited(engine.leaveChannel().then((_) => engine.release()).catchError((_) {}));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.headset_mic_rounded, color: Color(0xFF168B87)), const SizedBox(width: 8),
        const Expanded(child: Text('Voice Chat', style: TextStyle(fontWeight: FontWeight.w900))),
        if (_joined) Text('${_remoteUsers.length + 1} जुड़े', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w700)),
        if (_joining) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        if (!_joined) FilledButton.tonalIcon(onPressed: _joining ? null : _join, icon: const Icon(Icons.mic), label: const Text('Join Voice')),
        if (_joined) ...[
          OutlinedButton.icon(onPressed: _toggleMute, icon: Icon(_muted ? Icons.mic_off : Icons.mic), label: Text(_muted ? 'Unmute' : 'Mute')),
          OutlinedButton.icon(onPressed: _leave, icon: const Icon(Icons.call_end, color: Colors.red), label: const Text('Leave')),
        ],
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
      if (!_joined && !_joining && _error == null) const Text('सभी खिलाड़ी एक ही Room Code पर Voice Chat में जुड़ सकते हैं।', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
    ]),
  ));
}