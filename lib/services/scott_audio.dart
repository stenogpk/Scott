import 'package:audioplayers/audioplayers.dart';

class ScottAudio {
  ScottAudio._();
  static final ScottAudio instance = ScottAudio._();
  final AudioPlayer _player = AudioPlayer();
  bool enabled = true;
  double volume = 0.7;

  Future<void> play(String effect) async {
    if (!enabled) return;
    const allowed = {
      'card_discard', 'card_draw', 'previous_pickup', 'show',
      'failed_show', 'elimination', 'winner', 'shuffle', 'tap',
    };
    if (!allowed.contains(effect)) return;
    try {
      await _player.stop();
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.play(AssetSource('sounds/$effect.wav'));
    } catch (_) {
      // Sound is optional; gameplay must continue if an audio asset is unavailable.
    }
  }

  Future<void> dispose() => _player.dispose();
}
