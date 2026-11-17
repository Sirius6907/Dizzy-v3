import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cloud/remote_config_service.dart';
import 'hardcoded_channels.dart';
import 'iptv_controller.dart';
import 'iptv_storage.dart';

/// The channel that owns hero slot #1.
class CricketPin {
  final HardcodedChannel channel;
  final String label;

  const CricketPin({required this.channel, required this.label});

  @override
  bool operator ==(Object other) =>
      other is CricketPin &&
      other.channel.id == channel.id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(channel.id, label);

  @override
  String toString() => 'CricketPin(${channel.id}, $label)';
}

/// Live TV cricket priority.
///
/// "If Indian cricket is available, make it #1. If not, leave the list alone."
///
/// - The ranked channel ids live in remote config `live_tv_priority` so the
///   board can be re-ordered without a release. A missing or malformed value
///   falls back to [defaultOrder] (fail-closed, never grants anything).
/// - Availability is the presence of stored live hits for that channel. That
///   is the same evidence the channel sheet uses, so a pin can never point at
///   a channel that has never produced a working stream.
/// - Re-checked on start, whenever remote config lands, and every
///   [refreshInterval] (15 min). No portal scraping here: this only reads the
///   hit cache.
class CricketPriority extends ChangeNotifier {
  CricketPriority._();
  static final CricketPriority instance = CricketPriority._();
  factory CricketPriority() => instance;

  static const String configKey = 'live_tv_priority';
  static const String defaultLabel = 'INDIA CRICKET LIVE';
  static const Duration refreshInterval = Duration(minutes: 15);

  /// Shipped ranking. India-first: Star Sports, Sports18, Sony Ten, Willow,
  /// then the free-to-air DD Sports. Remote config overrides the whole list.
  static const List<String> defaultOrder = [
    'star_sports_1',
    'star_sports_2',
    'star_sports_select_1',
    'star_sports_hindi',
    'sports18_1',
    'sony_ten_1',
    'sony_ten_2',
    'sony_ten_3',
    'sony_ten_5',
    'willow_cricket',
    'dd_sports',
  ];

  CricketPin? _pin;
  CricketPin? get pin => _pin;
  bool get hasPin => _pin != null;

  Timer? _timer;
  bool _started = false;
  bool _refreshing = false;

  /// Idempotent. Safe to call from every Live TV page build.
  void start() {
    if (_started) {
      unawaited(refresh());
      return;
    }
    _started = true;
    RemoteConfigService.revision.addListener(_onConfigChanged);
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    RemoteConfigService.revision.removeListener(_onConfigChanged);
    _timer?.cancel();
    _timer = null;
  }

  void _onConfigChanged() => unawaited(refresh());

  /// Ranked ids requested by config, or the shipped order.
  List<String> order() {
    final parsed = parseOrder(RemoteConfigService.typedValue(configKey));
    return parsed.isEmpty ? defaultOrder : parsed;
  }

  /// Badge text requested by config, or the shipped label.
  String label() {
    return parseLabel(RemoteConfigService.typedValue(configKey)) ??
        defaultLabel;
  }

  /// Recomputes the pin. Cheap: cached hits only, no network.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final ranked = order();
      final available = <String, bool>{};
      for (final id in ranked) {
        available[id] = await isAvailable(id);
      }
      final next = choosePin(
        order: ranked,
        available: available,
        label: label(),
      );
      if (next == _pin) return;
      _pin = next;
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  /// True when this channel has at least one known working stream.
  Future<bool> isAvailable(String channelId) async {
    final ctrl = IptvController.instance;
    if (ctrl.activeHardcoded?.id == channelId &&
        ctrl.channelResults.isNotEmpty) {
      return true;
    }
    try {
      final hits = await IptvChannelResultsStore.load(channelId);
      return hits.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Parses `live_tv_priority`. Accepts both a bare array and the object form
  /// `{"channels": [...], "label": "..."}` (also `order`/`ids`/`priority`).
  /// Returns an empty list for anything unparseable so the caller can fall
  /// back instead of pinning garbage.
  static List<String> parseOrder(String raw) {
    final decoded = _decode(raw);
    List<dynamic>? list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      for (final key in const ['channels', 'order', 'ids', 'priority']) {
        final v = decoded[key];
        if (v is List) {
          list = v;
          break;
        }
      }
    }
    if (list == null) return const [];
    final out = <String>[];
    for (final entry in list) {
      final id = entry.toString().trim().toLowerCase();
      if (id.isEmpty || out.contains(id)) continue;
      out.add(id);
    }
    return out;
  }

  /// Parses the optional badge text from the same config value.
  static String? parseLabel(String raw) {
    final decoded = _decode(raw);
    if (decoded is! Map) return null;
    final label = decoded['label'];
    if (label is! String) return null;
    final trimmed = label.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// First ranked id that is both available and present in the catalog.
  /// Null means "no cricket today" — the page then renders exactly as before.
  static CricketPin? choosePin({
    required List<String> order,
    required Map<String, bool> available,
    String label = defaultLabel,
  }) {
    for (final id in order) {
      if (available[id] != true) continue;
      final channel = HardcodedChannels.byId(id);
      if (channel != null) return CricketPin(channel: channel, label: label);
    }
    return null;
  }

  static dynamic _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
