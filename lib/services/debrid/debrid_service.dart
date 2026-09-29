import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'debrid_resolver.dart';
import 'models/debrid_file.dart';
import 'providers/alldebrid_service.dart';
import 'providers/debrid_link_service.dart';
import 'providers/premiumize_service.dart';
import 'providers/real_debrid_service.dart';
import 'providers/torbox_service.dart';

class DebridService {
  static final DebridService _instance = DebridService._internal();
  factory DebridService() => _instance;
  DebridService._internal();

  final realDebrid = RealDebridService();
  final torBox = TorBoxService();
  final allDebrid = AllDebridService();
  final premiumize = PremiumizeService();
  final debridLink = DebridLinkService();

  static const String _debridServiceKey = 'debrid_service';
  static const String _useDebridForStreamsKey = 'use_debrid_for_streams';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Active Service Selection ───────────────────────────────────────────────

  Future<String> getSelectedService() async {
    final prefs = await _prefs;
    return prefs.getString(_debridServiceKey) ?? 'None';
  }

  Future<void> saveSelectedService(String service) async {
    final prefs = await _prefs;
    await prefs.setString(_debridServiceKey, service.trim());
  }

  // ── "Use Debrid for streams" Toggle ────────────────────────────────────────

  Future<bool> getUseDebridForStreams() async {
    final prefs = await _prefs;
    return prefs.getBool(_useDebridForStreamsKey) ?? false;
  }

  Future<void> saveUseDebridForStreams(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_useDebridForStreamsKey, value);
  }

  /// Returns true if Debrid is fully setup AND the "Use Debrid for streams" toggle is ON.
  Future<bool> isDebridActiveForStreams() async {
    final enabled = await getUseDebridForStreams();
    if (!enabled) return false;

    final service = await getSelectedService();
    if (service == 'None' || service.isEmpty) return false;

    return await hasKeyForService(service);
  }

  Future<bool> hasKeyForService(String service) async {
    switch (service) {
      case 'Real-Debrid':
        return await realDebrid.hasKey();
      case 'TorBox':
        return await torBox.hasKey();
      case 'AllDebrid':
        return await allDebrid.hasKey();
      case 'Premiumize':
        return await premiumize.hasKey();
      case 'Debrid-Link':
        return await debridLink.hasKey();
      default:
        return false;
    }
  }

  // ── Stream Resolution Dispatcher ──────────────────────────────────────────

  /// P3 — the failover chain, shared process-wide so its ordering and
  /// its reporting stay consistent across every call site.
  static final DebridResolver _resolver = DebridResolver();

  /// Resolve a magnet, falling through the provider chain on failure.
  ///
  /// [service] pins the chain when supplied: the chosen provider is
  /// tried first and the rest of the chain still runs behind it. That
  /// keeps a deliberate user choice (and every existing caller that
  /// passes one) working, while turning a dead provider from a hard
  /// failure into a slower success.
  ///
  /// Still throws when nothing could resolve — the old contract, and
  /// every caller already handles it. New callers that want the
  /// structured answer should call [DebridResolver.resolve] directly.
  Future<List<DebridFile>> resolveMagnet({
    required String magnet,
    String? service,
    int? fileIndex,
    String? filename,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final activeService = service ?? await getSelectedService();
    final pinned = _normalizeLabel(activeService);

    final result = await _resolver.resolve(
      magnet: magnet,
      fileIndex: fileIndex,
      filename: filename,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
    );
    if (result.isResolved) return result.files;

    // Pinned-but-unconfigured is the one case worth distinguishing: the
    // user asked for a service that has no key, and silently using a
    // different one would be surprising. The chain still ran, so if it
    // found nothing, say so plainly.
    if (result.attempted.isEmpty) {
      if (pinned != null) {
        throw Exception(
          'No Debrid key saved for $pinned. Please add it in Settings.',
        );
      }
      throw Exception('No Debrid service is set up. Please add a key in Settings.');
    }
    throw Exception(
      'Every Debrid service failed (${result.attempted.join(', ')}). '
      'Check your connection or keys in Settings.',
    );
  }

  /// Settings stores display names; the chain stores labels. This is the
  /// single place that reconciles them, so the two cannot drift.
  static String? _normalizeLabel(String service) {
    switch (service.trim()) {
      case 'Real-Debrid':
        return 'Real-Debrid';
      case 'TorBox':
        return 'TorBox';
      case 'AllDebrid':
        return 'AllDebrid';
      case 'Premiumize':
        return 'Premiumize';
      case 'Debrid-Link':
        return 'Debrid-Link';
      case 'None':
      case '':
        return null;
      default:
        return service.trim();
    }
  }

  /// The provider order the settings page should display, so the user
  /// can see the failover chain before it ever runs.
  static List<String> failoverOrder() =>
      _resolver.chain().map((a) => a.label).toList(growable: false);
}
