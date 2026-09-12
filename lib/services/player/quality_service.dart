/// P7 — Manual quality (rendition picker).
///
/// Gear → Quality menu: Auto + 480/720/1080/1440/2160 — but only what the
/// source actually has (zero-tech law: never offer a dead choice).
///  - HLS (.m3u8): cap via mpv `hls-bitrate-max` (master adapts itself).
///  - Progressive: switch to the ranked source file with the matching badge.
///  - Auto is the default and means "hands off" (P8 drives it by speed).
/// Choice persists per device.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stream/stream_model.dart';

/// Manual quality options. 480p floor, 4K cap (P7 spec).
enum QualityChoice {
  auto('Auto', null),
  q480('480p', 1000000),
  q720('720p', 2800000),
  q1080('1080p', 6000000),
  q1440('1440p', 12000000),
  q2160('2160p', 30000000);

  /// UI label. Never techy.
  final String label;

  /// mpv `hls-bitrate-max` cap in bits/sec. Null = no cap (Auto).
  final int? maxBitrate;

  const QualityChoice(this.label, this.maxBitrate);

  /// Badge text (StreamSource.quality / BrainRendition.label) → choice.
  /// '4K' maps to 2160p; unknown badges → null (never offered).
  static QualityChoice? fromBadge(String? badge) {
    switch ((badge ?? '').trim().toLowerCase()) {
      case '480p':
        return QualityChoice.q480;
      case '720p':
        return QualityChoice.q720;
      case '1080p':
        return QualityChoice.q1080;
      case '1440p':
        return QualityChoice.q1440;
      case '2160p':
      case '4k':
      case 'uhd':
        return QualityChoice.q2160;
      default:
        return null;
    }
  }
}

/// Owns the persisted manual quality choice + matching logic.
/// The player widget owns applying it to mpv (service stays UI-free).
class QualityService {
  static const prefsKey = 'dizzy_quality_choice_v1';

  QualityChoice _current = QualityChoice.auto;
  QualityChoice get current => _current;

  /// Load the saved per-device choice (Auto when never set).
  Future<QualityChoice> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      _current = QualityChoice.values.asNameMap()[raw] ?? QualityChoice.auto;
    } catch (_) {
      _current = QualityChoice.auto; // fail-soft: prefs broken → Auto
    }
    return _current;
  }

  /// Save the choice (fire-and-forget safe — failure keeps memory value).
  Future<void> save(QualityChoice choice) async {
    _current = choice;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, choice.name);
    } catch (_) {}
  }

  /// Menu options for the CURRENT video. Auto always first.
  /// HLS adapts by itself → all 5 offered. Progressive → only badges
  /// present across the candidate files (current + ranked backups).
  /// [renditionLabels] (P9): exact ladder labels of the current source —
  /// offered as-is so every rung is one tap away.
  static List<QualityChoice> optionsFor({
    required bool isHls,
    required Set<String> badges,
    Set<String> renditionLabels = const {},
  }) {
    if (isHls) return QualityChoice.values.toList();
    final found = <QualityChoice>{
      for (final b in {...badges, ...renditionLabels})
        if (QualityChoice.fromBadge(b) != null) QualityChoice.fromBadge(b)!,
    };
    const order = [
      QualityChoice.q480,
      QualityChoice.q720,
      QualityChoice.q1080,
      QualityChoice.q1440,
      QualityChoice.q2160,
    ];
    return [QualityChoice.auto, ...order.where(found.contains)];
  }

  /// First ranked source whose badge matches [choice] (progressive switch).
  /// Returns null when nothing matches — caller toasts, never dead-ends.
  /// [avoidAv1]: weak/straining device → skip AV1 files first (software
  /// decode melts small GPUs); falls back to AV1 when nothing else matches.
  static StreamSource? matchProgressive(
    List<StreamSource> ranked,
    QualityChoice choice, {
    bool avoidAv1 = false,
  }) {
    if (choice == QualityChoice.auto) return null;
    StreamSource? av1Fallback;
    for (final s in ranked) {
      if (QualityChoice.fromBadge(s.quality) != choice) continue;
      if (avoidAv1 && (s.codec ?? '').toUpperCase() == 'AV1') {
        av1Fallback ??= s;
        continue;
      }
      return s;
    }
    return av1Fallback;
  }

  /// True when [url] is an HLS master playlist (query/fragment ignored).
  static bool isHlsUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.toLowerCase().split('?').first.split('#').first.endsWith('.m3u8');
  }

  /// HUD toast after applying. Auto gets the reassuring suffix.
  static String toastFor(QualityChoice choice) => choice == QualityChoice.auto
      ? 'Quality: Auto (best for your speed)'
      : 'Quality: ${choice.label}';
}
