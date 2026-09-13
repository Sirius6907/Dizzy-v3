import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_player_controller.dart';
import 'music_settings.dart';

enum MusicEqPreset {
  flat,
  bassBoost,
  vocalBoost,
  trebleBoost,
  electronic,
  rock,
  acoustic,
  custom,
}

class MusicEqualizerService {
  MusicEqualizerService._();
  static final MusicEqualizerService instance = MusicEqualizerService._();

  static const String _keyEnabled = 'eq_enabled';
  static const String _keyPreset = 'eq_preset';
  static const String _keyBands = 'eq_bands_';
  static const String _keyBassBoost = 'eq_bass_boost';
  static const String _keySpatializer = 'eq_spatializer';

  final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<MusicEqPreset> currentPreset = ValueNotifier<MusicEqPreset>(MusicEqPreset.flat);
  final ValueNotifier<double> bassBoostLevel = ValueNotifier<double>(0.0); // 0.0 to 1.0
  final ValueNotifier<bool> enable3dSpatializer = ValueNotifier<bool>(false);

  // 5 Frequency Bands (60Hz, 250Hz, 1kHz, 4kHz, 16kHz) in dB (-12.0 to +12.0)
  final ValueNotifier<List<double>> bandGains = ValueNotifier<List<double>>([0.0, 0.0, 0.0, 0.0, 0.0]);

  static const Map<MusicEqPreset, List<double>> presetGains = {
    MusicEqPreset.flat: [0.0, 0.0, 0.0, 0.0, 0.0],
    MusicEqPreset.bassBoost: [7.5, 5.0, 1.0, 0.0, 0.0],
    MusicEqPreset.vocalBoost: [-2.0, 1.0, 6.0, 3.5, 1.0],
    MusicEqPreset.trebleBoost: [-1.0, 0.0, 2.0, 6.0, 8.5],
    MusicEqPreset.electronic: [6.0, 3.5, -1.0, 2.5, 5.0],
    MusicEqPreset.rock: [5.0, 3.0, -0.5, 4.0, 6.0],
    MusicEqPreset.acoustic: [2.0, 1.0, 3.5, 4.0, 3.0],
    MusicEqPreset.custom: [0.0, 0.0, 0.0, 0.0, 0.0],
  };

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled.value = prefs.getBool(_keyEnabled) ?? false;

      final presetName = prefs.getString(_keyPreset);
      currentPreset.value = MusicEqPreset.values.firstWhere(
        (p) => p.name == presetName,
        orElse: () => MusicEqPreset.flat,
      );

      bassBoostLevel.value = prefs.getDouble(_keyBassBoost) ?? 0.0;
      enable3dSpatializer.value = prefs.getBool(_keySpatializer) ?? false;

      final savedBands = <double>[];
      for (int i = 0; i < 5; i++) {
        savedBands.add(prefs.getDouble('$_keyBands$i') ?? (presetGains[currentPreset.value]?[i] ?? 0.0));
      }
      bandGains.value = savedBands;

      // Apply initial filters if enabled
      applyFilters();
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    isEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
    await applyFilters();
  }

  Future<void> setPreset(MusicEqPreset preset) async {
    currentPreset.value = preset;
    if (preset != MusicEqPreset.custom) {
      final defaultGains = presetGains[preset] ?? [0.0, 0.0, 0.0, 0.0, 0.0];
      bandGains.value = List<double>.from(defaultGains);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, preset.name);
    await applyFilters();
  }

  Future<void> setBandGain(int index, double gainDb) async {
    if (index < 0 || index >= 5) return;
    currentPreset.value = MusicEqPreset.custom;
    final updated = List<double>.from(bandGains.value);
    updated[index] = gainDb.clamp(-12.0, 12.0);
    bandGains.value = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, MusicEqPreset.custom.name);
    await prefs.setDouble('$_keyBands$index', updated[index]);
    await applyFilters();
  }

  Future<void> setBassBoostLevel(double level) async {
    bassBoostLevel.value = level.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBassBoost, bassBoostLevel.value);
    await applyFilters();
  }

  Future<void> set3dSpatializer(bool enable) async {
    enable3dSpatializer.value = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpatializer, enable);
    await applyFilters();
  }

  /// Builds the ffmpeg / libmpv audio filter string and sets it on player.platform
  Future<void> applyFilters() async {
    final player = MusicPlayerController.instance.player;
    if (player == null) return;

    if (!isEnabled.value) {
      try {
        await (player.platform as dynamic).setProperty('af', '');
      } catch (_) {}
      return;
    }

    final filters = <String>[];

    // 1. 5-Band Equalizer (firequalizer or equalizer)
    final gains = bandGains.value;
    if (gains.length == 5) {
      final f60 = gains[0];
      final f250 = gains[1];
      final f1k = gains[2];
      final f4k = gains[3];
      final f16k = gains[4];

      if (f60 != 0 || f250 != 0 || f1k != 0 || f4k != 0 || f16k != 0) {
        filters.add(
          'equalizer=f=60:width_type=o:w=1:g=$f60,'
          'equalizer=f=250:width_type=o:w=1:g=$f250,'
          'equalizer=f=1000:width_type=o:w=1:g=$f1k,'
          'equalizer=f=4000:width_type=o:w=1:g=$f4k,'
          'equalizer=f=16000:width_type=o:w=1:g=$f16k',
        );
      }
    }

    // 2. Extra Bass Boost Knob
    if (bassBoostLevel.value > 0.05) {
      final boostGain = (bassBoostLevel.value * 9.0).toStringAsFixed(1);
      filters.add('equalizer=f=75:width_type=h:width=60:g=$boostGain');
    }

    // 3. 3D Audio Spatializer / Extrastereo
    if (enable3dSpatializer.value) {
      filters.add('extrastereo=m=1.65');
    }

    // 4. Smart Volume Normalization (Dynamic Audio Normalizer - dynaudnorm)
    if (MusicSettings.enableSmartVolumeNormalization.value) {
      filters.add('dynaudnorm=f=120:g=15:m=10.0');
    }

    final afString = filters.join(',');
    try {
      await (player.platform as dynamic).setProperty('af', afString);
    } catch (_) {}
  }
}
