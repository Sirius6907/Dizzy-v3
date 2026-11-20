import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the room mic sounds, in three words a person can choose between.
///
/// This is the setting people actually need for one reason: watch-party voice
/// competes with whatever is playing through the speaker. A voice call at
/// 48 kbps over a phone hotspot sounds like a robot reading a shopping list,
/// so the app lets you trade clarity for data instead of deciding for you.
///
/// Echo cancellation, noise suppression and voice isolation stay on in every
/// tier — with a film playing out loud, turning those off is not a "quality
/// choice", it is a broken call.
enum PartyVoiceQuality {
  /// Wi-Fi, headphones, nothing else on the network.
  high,

  /// The default. Clear speech at roughly 24 kbps.
  balanced,

  /// Weak mobile data. Narrowband but perfectly understandable.
  dataSaver,
}

extension PartyVoiceQualityInfo on PartyVoiceQuality {
  String get label => switch (this) {
    PartyVoiceQuality.high => 'Clear',
    PartyVoiceQuality.balanced => 'Balanced',
    PartyVoiceQuality.dataSaver => 'Save data',
  };

  /// One short line, shown under the picker. No bitrate jargon.
  String get hint => switch (this) {
    PartyVoiceQuality.high => 'Best sound on Wi-Fi. Uses the most data.',
    PartyVoiceQuality.balanced => 'Clear voice. Good on most connections.',
    PartyVoiceQuality.dataSaver => 'Uses the least data. Fine for talking.',
  };

  AudioEncoding get encoding => switch (this) {
    PartyVoiceQuality.high => AudioEncoding.presetMusic,
    PartyVoiceQuality.balanced => AudioEncoding.presetSpeech,
    PartyVoiceQuality.dataSaver => AudioEncoding.presetTelephone,
  };

  AudioPublishOptions get publishOptions => AudioPublishOptions(
    encoding: encoding,
    // DTX stops sending packets while nobody talks: the single biggest
    // saving when four people sit in a room saying nothing for ten minutes.
    dtx: true,
    // Redundant audio costs ~30% more bytes but hides packet loss. Not worth
    // it on the tier whose whole purpose is spending less.
    red: this != PartyVoiceQuality.dataSaver,
  );

  AudioCaptureOptions get captureOptions => const AudioCaptureOptions(
    noiseSuppression: true,
    echoCancellation: true,
    autoGainControl: true,
    voiceIsolation: true,
    // A film's bass rumbles under every voice; the high-pass filter removes
    // it before it is encoded, which is free quality on a cheap mic.
    highPassFilter: true,
  );
}

/// Persisted voice-quality choice + the [RoomOptions] it produces.
///
/// Read once on first voice join, so a cold start never blocks on prefs.
abstract final class PartyVoiceQualityService {
  static const String _prefsKey = 'party_voice_quality_v1';

  static final ValueNotifier<PartyVoiceQuality> current =
      ValueNotifier<PartyVoiceQuality>(PartyVoiceQuality.balanced);

  static bool _loaded = false;

  /// Loads the saved choice. Safe to call repeatedly; never throws.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      for (final q in PartyVoiceQuality.values) {
        if (q.name == saved) {
          current.value = q;
          return;
        }
      }
    } catch (e) {
      debugPrint('[VoiceQuality] load skipped: $e');
    }
  }

  /// Saves the choice. Takes effect on the next join — LiveKit applies
  /// capture/publish options when the room connects, so a live call keeps
  /// its current encoding rather than restarting the mic mid-sentence.
  static Future<void> set(PartyVoiceQuality quality) async {
    current.value = quality;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, quality.name);
    } catch (e) {
      debugPrint('[VoiceQuality] save skipped: $e');
    }
  }

  /// The options the room should be built with. Pure.
  static RoomOptions roomOptions([PartyVoiceQuality? quality]) {
    final q = quality ?? current.value;
    return RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultAudioCaptureOptions: q.captureOptions,
      defaultAudioPublishOptions: q.publishOptions,
    );
  }
}
