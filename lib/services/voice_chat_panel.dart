import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String _voiceTokenEndpoint = 'https://scott-voice-token.theshartendu.workers.dev';

enum _VoiceConnectionStatus { disconnected, joining, connected, reconnecting, failed }

class VoiceChatPanel extends StatefulWidget {
  const VoiceChatPanel({super.key, required this.roomCode, required this.getFirebaseIdToken});
  final String roomCode;
  final Future<String> Function() getFirebaseIdToken;

  @override
  State<VoiceChatPanel> createState() => _VoiceChatPanelState();
}

class _VoiceChatPanelState extends State<VoiceChatPanel> with WidgetsBindingObserver {
  RtcEngine? _engine;
  bool _joining = false;
  bool _joined = false;
  bool _muted = false;
  bool _speakerEnabled = false;
  bool _renewingToken = false;
  final Set<int> _speakingUsers = <int>{};
  String? _error;
  String? _connectionDetail;
  _VoiceConnectionStatus _connectionStatus = _VoiceConnectionStatus.disconnected;
  final Map<int, String> _participantNames = {};
  final Set<int> _remoteUsers = <int>{};
  final Set<int> _mutedRemoteUsers = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do not force a leave/rejoin here: Agora owns transient network recovery.
    // Record the lifecycle transition for the status panel and re-check state
    // when the user returns to the game.
    if (state == AppLifecycleState.resumed && mounted && _joined) {
      setState(() => _connectionDetail = 'ऐप वापस सक्रिय हुआ');
    }
  }

  Future<Map<String, dynamic>> _requestVoiceToken() async {
    final idToken = await widget.getFirebaseIdToken();
    final response = await http.post(
      Uri.parse('$_voiceTokenEndpoint/rtc-token'),
      headers: {'content-type': 'application/json', 'authorization': 'Bearer $idToken'},
      body: jsonEncode({'roomCode': widget.roomCode}),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      dynamic body;
      try { body = jsonDecode(response.body); } catch (_) {}
      throw StateError(body is Map
          ? (body['error']?.toString() ?? 'Voice token request failed (${response.statusCode}).')
          : 'Voice token request failed (${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _renewVoiceToken(RtcEngine engine) async {
    if (_renewingToken || !identical(_engine, engine)) return;
    _renewingToken = true;
    try {
      final payload = await _requestVoiceToken();
      if (!identical(_engine, engine)) return;
      await engine.renewToken(payload['token'] as String);
      if (mounted) {
        setState(() {
          _connectionDetail = 'Voice Token नवीनीकृत';
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Voice Token renewal failed: $error');
    } finally {
      _renewingToken = false;
    }
  }

  void _setConnectionStatus(_VoiceConnectionStatus status, String detail) {
    if (!mounted) return;
    setState(() {
      _connectionStatus = status;
      _connectionDetail = detail;
      if (status == _VoiceConnectionStatus.connected) _error = null;
      if (status == _VoiceConnectionStatus.failed) {
        _joined = false;
        _joining = false;
      }
    });
  }

  Future<void> _join() async {
    if (_joining || _joined) return;
    setState(() {
      _joining = true;
      _connectionStatus = _VoiceConnectionStatus.joining;
      _connectionDetail = 'Voice Room से जुड़ रहे हैं…';
      _error = null;
    });
    RtcEngine? engine;
    try {
      // A terminal SDK failure can leave the previous engine allocated.
      // Release it before creating a fresh engine for an explicit retry.
      final previousEngine = _engine;
      _engine = null;
      if (previousEngine != null) {
        try { await previousEngine.leaveChannel(); } catch (_) {}
        try { await previousEngine.release(); } catch (_) {}
      }
      if (!kIsWeb) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          throw StateError('Voice Chat के लिए Microphone permission जरूरी है।');
        }
      }
      final payload = await _requestVoiceToken();
      final appId = payload['appId'] as String;
      final channel = payload['channel'] as String;
      final token = payload['token'] as String;
      final uid = (payload['uid'] as num).toInt();
      final rawParticipants = payload['participants'] as List? ?? const [];
      _participantNames.clear();
      for (final item in rawParticipants) {
        if (item is Map) {
          final participantUid = (item['uid'] as num?)?.toInt();
          if (participantUid != null) {
            _participantNames[participantUid] = item['name']?.toString() ?? 'खिलाड़ी';
          }
        }
      }

      engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      await engine.enableAudio();
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          if (mounted && identical(_engine, engine)) {
            setState(() {
              _joined = true;
              _joining = false;
              _connectionStatus = _VoiceConnectionStatus.connected;
              _connectionDetail = 'Voice Connected';
              _error = null;
            });
          }
        },
        onRejoinChannelSuccess: (connection, elapsed) {
          _setConnectionStatus(_VoiceConnectionStatus.connected, 'कनेक्शन वापस आ गया');
        },
        onConnectionStateChanged: (connection, state, reason) {
          switch (state) {
            case ConnectionStateType.connectionStateConnected:
              _setConnectionStatus(_VoiceConnectionStatus.connected, 'Voice Connected');
              break;
            case ConnectionStateType.connectionStateReconnecting:
              _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क दोबारा जुड़ रहा है…');
              break;
            case ConnectionStateType.connectionStateFailed:
              _setConnectionStatus(_VoiceConnectionStatus.failed, 'कनेक्शन बहाल नहीं हो पाया');
              break;
            case ConnectionStateType.connectionStateConnecting:
              _setConnectionStatus(_VoiceConnectionStatus.joining, 'Voice Room से जुड़ रहे हैं…');
              break;
            case ConnectionStateType.connectionStateDisconnected:
              // A deliberate Leave also produces Disconnected; do not turn it
              // into an error or start a second join from this callback.
              if (_connectionStatus != _VoiceConnectionStatus.disconnected) {
                _setConnectionStatus(_VoiceConnectionStatus.disconnected, 'Voice Disconnected');
              }
              break;
          }
        },
        onConnectionInterrupted: (connection) {
          _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क कनेक्शन बाधित है…');
        },
        onConnectionLost: (connection) {
          // Agora continues its own retry process after this callback.
          _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क कमजोर है; दोबारा जुड़ने की कोशिश जारी है…');
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          final currentEngine = _engine;
          if (currentEngine != null) unawaited(_renewVoiceToken(currentEngine));
        },
        onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
          if (!mounted) return;
          final active = speakers.where((speaker) => speaker.volume > 8 && speaker.uid != 0).map((speaker) => speaker.uid).toSet();
          setState(() {
            _speakingUsers
              ..clear()
              ..addAll(active);
          });
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() => _remoteUsers.add(remoteUid));
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted) {
            setState(() {
              _remoteUsers.remove(remoteUid);
              _mutedRemoteUsers.remove(remoteUid);
              _speakingUsers.remove(remoteUid);
            });
          }
        },
        onError: (err, msg) {
          if (mounted) setState(() => _error = 'Agora error $err: $msg');
        },
      ));
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
        ),
      );
      try { await engine.enableAudioVolumeIndication(interval: 300, smooth: 3, reportVad: true); } catch (_) {}
      if (mounted) setState(() => _joining = false);
    } catch (error) {
      if (identical(_engine, engine)) _engine = null;
      try { await engine?.leaveChannel(); } catch (_) {}
      try { await engine?.release(); } catch (_) {}
      if (mounted) {
        setState(() {
          _joining = false;
          _joined = false;
          _connectionStatus = _VoiceConnectionStatus.failed;
          _connectionDetail = 'Voice में जुड़ना विफल हुआ';
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<void> _toggleMic() async {
    final next = !_muted;
    try {
      await _engine?.muteLocalAudioStream(next);
      if (mounted) setState(() => _muted = next);
    } catch (error) {
      if (mounted) setState(() => _error = 'Mic setting failed: $error');
    }
  }

  Future<void> _toggleRemoteSpeaker(int uid) async {
    final next = !_mutedRemoteUsers.contains(uid);
    try {
      await _engine?.muteRemoteAudioStream(uid: uid, mute: next);
      if (mounted) {
        setState(() {
          if (next) { _mutedRemoteUsers.add(uid); } else { _mutedRemoteUsers.remove(uid); }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Player audio setting failed: $error');
    }
  }

  Future<void> _toggleSpeakerRoute() async {
    final next = !_speakerEnabled;
    try {
      await _engine?.setEnableSpeakerphone(next);
      if (mounted) setState(() => _speakerEnabled = next);
    } catch (error) {
      if (mounted) setState(() => _error = 'Audio output setting failed: $error');
    }
  }

  Future<void> _leave() async {
    final engine = _engine;
    _engine = null;
    try { await engine?.leaveChannel(); } catch (_) {}
    try { await engine?.release(); } catch (_) {}
    if (mounted) {
      setState(() {
        _joined = false;
        _joining = false;
        _muted = false;
        _speakerEnabled = false;
        _connectionStatus = _VoiceConnectionStatus.disconnected;
        _connectionDetail = null;
        _remoteUsers.clear();
        _mutedRemoteUsers.clear();
        _speakingUsers.clear();
        _participantNames.clear();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      unawaited(engine.leaveChannel().then((_) => engine.release()).catchError((_) {}));
    }
    super.dispose();
  }

  String _nameFor(int uid) => _participantNames[uid] ?? 'Player $uid';

  Color get _statusColor {
    switch (_connectionStatus) {
      case _VoiceConnectionStatus.connected: return Colors.green;
      case _VoiceConnectionStatus.reconnecting: return Colors.orange;
      case _VoiceConnectionStatus.failed: return Colors.red;
      case _VoiceConnectionStatus.joining: return Colors.blue;
      case _VoiceConnectionStatus.disconnected: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.headset_mic_rounded, color: Color(0xFF168B87)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Voice Chat', style: TextStyle(fontWeight: FontWeight.w900))),
          if (_joined) Text('${_remoteUsers.length + 1} जुड़े',
              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w700)),
          if (_joining) const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (_connectionDetail != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(_connectionDetail!, style: TextStyle(fontSize: 11, color: _statusColor))),
            ]),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (!_joined)
            FilledButton.tonalIcon(
              onPressed: _joining ? null : _join,
              icon: const Icon(Icons.mic),
              label: Text(_connectionStatus == _VoiceConnectionStatus.failed ? 'Retry Voice' : 'Join Voice'),
            ),
          if (_joined) ...[
            OutlinedButton.icon(
              onPressed: _toggleMic,
              icon: Icon(_muted ? Icons.mic_off : Icons.mic),
              label: Text(_muted ? 'Unmute Mic' : 'Mute Mic'),
            ),
            if (!kIsWeb) OutlinedButton.icon(
              onPressed: _toggleSpeakerRoute,
              icon: Icon(_speakerEnabled ? Icons.volume_up : Icons.hearing),
              label: Text(_speakerEnabled ? 'Speaker ON' : 'Earpiece'),
            ),
            OutlinedButton.icon(
              onPressed: _leave,
              icon: const Icon(Icons.call_end, color: Colors.red),
              label: const Text('Leave'),
            ),
          ],
        ]),
        if (_joined) ...[
          const Divider(height: 16),
          const Text('Voice में जुड़े खिलाड़ी', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          if (_remoteUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('दूसरे खिलाड़ी के जुड़ने की प्रतीक्षा…', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ),
          for (final uid in _remoteUsers.toList()..sort())
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 17)),
              title: Text(_nameFor(uid), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_speakingUsers.contains(uid) ? 'बोल रहे हैं' : 'Connected', style: TextStyle(color: _speakingUsers.contains(uid) ? Colors.green : null)),
              trailing: IconButton(
                tooltip: _mutedRemoteUsers.contains(uid) ? 'Unmute this player' : 'Mute this player',
                onPressed: () => _toggleRemoteSpeaker(uid),
                icon: Icon(_mutedRemoteUsers.contains(uid) ? Icons.volume_off : Icons.volume_up),
              ),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        if (!_joined && !_joining && _error == null)
          const Text('सभी खिलाड़ी एक ही Room Code पर Voice Chat में जुड़ सकते हैं।',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
      ]),
    ),
  );
}
