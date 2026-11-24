import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
  bool _wantsVoice = false;
  bool _manualLeave = false;
  bool _tearingDown = false;
  bool _recoveryInProgress = false;
  int _retryAttempt = 0;
  int _engineGeneration = 0;
  final Set<int> _speakingUsers = <int>{};
  String? _error;
  String? _connectionDetail;
  String? _lastDisconnectReason;
  _VoiceConnectionStatus _connectionStatus = _VoiceConnectionStatus.disconnected;
  final Map<int, String> _participantNames = {};
  final Set<int> _remoteUsers = <int>{};
  final Set<int> _mutedRemoteUsers = <int>{};
  final Map<int, String> _networkQuality = <int, String>{};
  Timer? _joinTimeout;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _log(String message) {
    // Never log Firebase/Agora tokens or user credentials.
    debugPrint('[SCOTT-VOICE][${widget.roomCode}] $message');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('appLifecycle=$state wantsVoice=$_wantsVoice joined=$_joined');
    if (state == AppLifecycleState.resumed && mounted && _wantsVoice && !_joined && !_joining) {
      _scheduleReconnect('ऐप वापस सक्रिय हुआ; Voice कनेक्शन जाँच रहे हैं…', immediate: true);
    }
    // Do not leave on inactive/paused: iOS can briefly report these during
    // permission prompts, audio-session interruptions, and system overlays.
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
    if (_renewingToken || !identical(_engine, engine) || !_wantsVoice) return;
    _renewingToken = true;
    try {
      final payload = await _requestVoiceToken();
      if (!identical(_engine, engine) || !_wantsVoice) return;
      await engine.renewToken(payload['token'] as String);
      _log('tokenRenewed');
      if (mounted) {
        setState(() {
          _connectionDetail = 'Voice Token नवीनीकृत';
          _error = null;
        });
      }
    } catch (error) {
      _log('tokenRenewalFailed=$error');
      if (mounted) setState(() => _error = 'Token renewal में समस्या; दोबारा कनेक्ट कर रहे हैं…');
      _scheduleReconnect('Token नवीनीकरण विफल; दोबारा जुड़ रहे हैं…');
    } finally {
      _renewingToken = false;
    }
  }

  void _setConnectionStatus(_VoiceConnectionStatus status, String detail) {
    if (!mounted) return;
    setState(() {
      _connectionStatus = status;
      _connectionDetail = detail;
      if (status == _VoiceConnectionStatus.connected) {
        _joined = true;
        _joining = false;
        _retryAttempt = 0;
        _error = null;
      } else if (status == _VoiceConnectionStatus.reconnecting ||
          status == _VoiceConnectionStatus.failed ||
          status == _VoiceConnectionStatus.disconnected) {
        _joined = false;
      }
    });
  }

  void _scheduleReconnect(String reason, {bool immediate = false}) {
    if (!mounted || !_wantsVoice || _manualLeave || _reconnectTimer?.isActive == true) return;
    _joinTimeout?.cancel();
    _joined = false;
    _joining = false;
    _setConnectionStatus(_VoiceConnectionStatus.reconnecting, reason);
    final seconds = immediate ? 1 : (_retryAttempt < 5 ? (2 << _retryAttempt) : 30);
    _retryAttempt++;
    _log('reconnectScheduled attempt=$_retryAttempt delay=${seconds}s reason=$reason');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      if (mounted && _wantsVoice && !_manualLeave && !_joining && !_joined) {
        unawaited(_join(isRecovery: true));
      }
    });
  }

  Future<void> _disposeEngine(RtcEngine? engine) async {
    if (engine == null) return;
    _tearingDown = true;
    try { await engine.leaveChannel(); } catch (error) { _log('leaveDuringRecovery=$error'); }
    try { await engine.release(); } catch (error) { _log('releaseDuringRecovery=$error'); }
    _tearingDown = false;
  }

  Future<void> _join({bool isRecovery = false}) async {
    if (_joining || _joined || !_wantsVoice || _manualLeave) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    setState(() {
      _joining = true;
      _connectionStatus = isRecovery ? _VoiceConnectionStatus.reconnecting : _VoiceConnectionStatus.joining;
      _connectionDetail = isRecovery ? 'Voice अपने-आप दोबारा जुड़ रहा है…' : 'Voice Room से जुड़ रहे हैं…';
      _error = null;
    });
    RtcEngine? engine;
    final generation = ++_engineGeneration;
    try {
      final previousEngine = _engine;
      _engine = null;
      await _disposeEngine(previousEngine);
      if (!mounted || !_wantsVoice || _manualLeave || generation != _engineGeneration) return;
      if (!kIsWeb) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          throw StateError('Voice Chat के लिए Microphone permission जरूरी है।');
        }
      }
      final payload = await _requestVoiceToken();
      if (!mounted || !_wantsVoice || _manualLeave || generation != _engineGeneration) return;
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
          if (!mounted || !identical(_engine, engine)) return;
          _joinTimeout?.cancel();
          _setConnectionStatus(_VoiceConnectionStatus.connected, 'Voice Connected');
          _log('joinSuccess uid=${connection.localUid} elapsed=$elapsed');
        },
        onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
          if (!mounted || !identical(_engine, engine)) return;
          setState(() => _networkQuality[remoteUid] = rxQuality.name);
        },
        onUserMuteAudio: (connection, remoteUid, muted) {
          if (!mounted || !identical(_engine, engine)) return;
          setState(() {
            if (muted) { _mutedRemoteUsers.add(remoteUid); } else { _mutedRemoteUsers.remove(remoteUid); }
          });
        },
        onRejoinChannelSuccess: (connection, elapsed) {
          if (!identical(_engine, engine)) return;
          _setConnectionStatus(_VoiceConnectionStatus.connected, 'कनेक्शन वापस आ गया');
          _log('rejoinSuccess elapsed=$elapsed');
        },
        onConnectionStateChanged: (connection, state, reason) {
          if (!identical(_engine, engine) || _tearingDown || _manualLeave) return;
          _lastDisconnectReason = reason.name;
          _log('connectionState=$state reason=$reason');
          switch (state) {
            case ConnectionStateType.connectionStateConnected:
              _joinTimeout?.cancel();
              _setConnectionStatus(_VoiceConnectionStatus.connected, 'Voice Connected');
              break;
            case ConnectionStateType.connectionStateReconnecting:
              _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क दोबारा जुड़ रहा है…');
              break;
            case ConnectionStateType.connectionStateFailed:
              _scheduleReconnect('कनेक्शन विफल (Reason: ${reason.name}); दोबारा प्रयास जारी…');
              break;
            case ConnectionStateType.connectionStateConnecting:
              _setConnectionStatus(_VoiceConnectionStatus.joining, 'Voice Room से जुड़ रहे हैं…');
              break;
            case ConnectionStateType.connectionStateDisconnected:
              _scheduleReconnect('Voice कनेक्शन टूट गया (Reason: ${reason.name}); दोबारा जुड़ रहे हैं…');
              break;
          }
        },
        onConnectionInterrupted: (connection) {
          if (!identical(_engine, engine) || _manualLeave) return;
          _log('connectionInterrupted');
          _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क कनेक्शन बाधित है…');
        },
        onConnectionLost: (connection) {
          if (!identical(_engine, engine) || _manualLeave) return;
          _log('connectionLost');
          _setConnectionStatus(_VoiceConnectionStatus.reconnecting, 'नेटवर्क कमजोर है; कनेक्शन बहाल कर रहे हैं…');
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          if (!identical(_engine, engine)) return;
          unawaited(_renewVoiceToken(engine!));
        },
        onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
          if (!mounted || !identical(_engine, engine)) return;
          final active = <int>{};
          for (final speaker in speakers) {
            final uid = speaker.uid;
            final volume = speaker.volume ?? 0;
            if (uid != null && uid != 0 && volume > 8) active.add(uid);
          }
          setState(() {
            _speakingUsers
              ..clear()
              ..addAll(active);
          });
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted && identical(_engine, engine)) setState(() => _remoteUsers.add(remoteUid));
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted && identical(_engine, engine)) {
            _log('remoteUserOffline uid=$remoteUid reason=$reason');
            setState(() {
              _remoteUsers.remove(remoteUid);
              _mutedRemoteUsers.remove(remoteUid);
              _networkQuality.remove(remoteUid);
              _speakingUsers.remove(remoteUid);
            });
          }
        },
        onError: (err, msg) {
          if (!mounted || !identical(_engine, engine)) return;
          _log('agoraError code=$err message=$msg');
          setState(() => _error = 'Agora error $err: $msg');
        },
      ));
      _joinTimeout?.cancel();
      _joinTimeout = Timer(const Duration(seconds: 30), () {
        if (!mounted || _joined || !identical(_engine, engine) || !_wantsVoice) return;
        _log('joinTimeout generation=$generation');
        _scheduleReconnect('Voice कनेक्शन में देरी; अपने-आप फिर कोशिश हो रही है…');
      });
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
      try { await engine.enableAudioVolumeIndication(interval: 300, smooth: 3, reportVad: true); } catch (error) { _log('volumeIndicationUnavailable=$error'); }
      if (mounted && !_joined && _joining) setState(() => _joining = false);
    } catch (error) {
      _joinTimeout?.cancel();
      if (identical(_engine, engine)) _engine = null;
      await _disposeEngine(engine);
      _log('joinAttemptFailed recovery=$isRecovery error=$error');
      if (mounted && _wantsVoice && !_manualLeave) {
        setState(() {
          _joining = false;
          _joined = false;
          _connectionStatus = _VoiceConnectionStatus.reconnecting;
          _connectionDetail = 'Voice कनेक्शन नहीं हुआ; फिर कोशिश होगी…';
          _error = null;
        });
        _scheduleReconnect('Voice कनेक्शन असफल; स्वतः दोबारा प्रयास जारी…');
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
    _manualLeave = true;
    _wantsVoice = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _joinTimeout?.cancel();
    ++_engineGeneration;
    final engine = _engine;
    _engine = null;
    await _disposeEngine(engine);
    if (mounted) {
      setState(() {
        _joined = false;
        _joining = false;
        _muted = false;
        _speakerEnabled = false;
        _retryAttempt = 0;
        _connectionStatus = _VoiceConnectionStatus.disconnected;
        _connectionDetail = 'आपने Voice Chat छोड़ दी';
        _error = null;
        _remoteUsers.clear();
        _mutedRemoteUsers.clear();
        _speakingUsers.clear();
        _networkQuality.clear();
        _participantNames.clear();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wantsVoice = false;
    _manualLeave = true;
    _reconnectTimer?.cancel();
    _joinTimeout?.cancel();
    ++_engineGeneration;
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
          if (_joining || _connectionStatus == _VoiceConnectionStatus.reconnecting)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
          if (!_joined && !_wantsVoice)
            FilledButton.tonalIcon(
              onPressed: _joining ? null : () {
                _manualLeave = false;
                _wantsVoice = true;
                _retryAttempt = 0;
                unawaited(_join());
              },
              icon: const Icon(Icons.mic),
              label: const Text('Join Voice'),
            ),
          if (_wantsVoice && !_joined)
            OutlinedButton(
              onPressed: _leave,
              child: const Text('Cancel Reconnect'),
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
              subtitle: Text(
                '${_speakingUsers.contains(uid) ? 'बोल रहे हैं • ' : ''}${_mutedRemoteUsers.contains(uid) ? 'Mic बंद' : 'Connected'}${_networkQuality[uid] == null ? '' : ' • Network ${_networkQuality[uid]}'}',
                style: TextStyle(color: _speakingUsers.contains(uid) ? Colors.green : null),
              ),
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
        if (!_joined && !_wantsVoice)
          const Text('सभी खिलाड़ी एक ही Room Code पर Voice Chat में जुड़ सकते हैं।',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
      ]),
    ),
  );
}
