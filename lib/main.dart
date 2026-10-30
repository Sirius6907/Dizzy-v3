import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:window_manager/window_manager.dart';

import './pages/home/home_page.dart';
import './services/addon/addon_manager.dart';
import './services/adult/adult_section_gate.dart';
import './services/theme/app_theme_service.dart';
import './services/updater/update_gate.dart';
import './services/updater/update_orchestrator.dart';
import './services/updater/update_state_machine.dart';
import './services/books/continue_reading_service.dart';
import './services/books/reader_settings.dart';
import './services/continue_watching/continue_watching_service.dart';

import './services/media/global_media_coordinator.dart';
import './services/theme/dock_settings.dart';
import './services/theme/glass_settings.dart';
import './services/player/dub_mode_service.dart';
import './services/cloud/announcement_service.dart';
import './services/cloud/cloud_client.dart';
import './services/cloud/cloud_auth_service.dart';
import './services/cloud/remote_config_service.dart';
import './services/device/device_id_service.dart';
import './services/social/dizzy_identity_service.dart';
import './services/social/phone_link_service.dart';
import './services/social/username_gate_state.dart';
import './services/taste/taste_event_service.dart';
import './services/profiles/dizzy_profile_service.dart';
import './services/scraper/scraper_quarantine_service.dart';
import './services/audiobook/audiobook_settings.dart';
import './services/home/home_page_settings.dart';
import './services/iptv/iptv_controller.dart';
import './services/iptv/iptv_settings.dart';
import './utils/a11y/a11y.dart';
import './services/manga/manga_settings.dart';
import './services/music/music_download_service.dart';
import './services/music/music_settings.dart';
import './services/music/qobuz_music_service.dart';
import './services/my_list/my_list_service.dart';
import './services/player/player_settings.dart';
import './services/download/download_service.dart';
import './services/errors/app_error_log.dart';
import './services/errors/session_trail.dart';
import './services/support/support_agent_service.dart';
import './services/config/env_service.dart';
import './services/window/window_service.dart';
import './services/p2p/p2p_settings_service.dart';
import './services/discord/discord_rpc_service.dart';
import './widgets/updater/update_dialog.dart';
import './pages/common/device_revoked_screen.dart';
import './pages/common/ban_notice_screen.dart';
import './pages/common/update_required_screen.dart';
import './services/moderation/ban_service.dart';
import './services/messaging/dm_outbox.dart';
import './services/messaging/oem_kill_detector.dart';
import './services/notification/notification_service.dart';
import './services/notification/notification_triggers.dart';
import './services/push/push_service.dart';
import './services/social/dizzy_social_service.dart';
import './core/error_boundary.dart';
import './core/nav_key.dart';
import './pages/search/universal_spotlight_modal.dart';
import './services/system/resource_governor.dart';
import './services/system/desktop_database.dart';
import './utils/perf/performance_mode.dart';
import './services/watchparty/party_session.dart';
import './services/heartbeat/heartbeat_service.dart';
import './services/media/media_session_bridge.dart';
import './services/watchparty/voice_background_gate.dart';
import './services/watchparty/guest_auto_open.dart';

/// Runs one boot initializer in isolation: a single failing service must not
/// abort boot before runApp (that used to leave a permanent black window).
Future<void> _safeInit(String name, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e, st) {
    unawaited(
      AppErrorLog.log(code: 'E_BOOT', screen: 'boot', detail: '$name: $e'),
    );
    if (kDebugMode) debugPrint('[boot] $name failed: $e\n$st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // v1.2.0-T3.2: global error boundary — branded screen, never white-screen.
  // Installed BEFORE boot work: anything below may throw, and without this
  // the process would idle on a black window because runApp never runs.
  installGlobalErrorHandlers(restartApp: () => runApp(const DizzyApp()));
  // Desktop DB FIRST (2026-10-10): sqflite has no Windows/Linux plugin —
  // without the FFI backend, CachedNetworkImage's disk cache throws on
  // first write and every remote image stays blank. Must run before any
  // widget/painting touches an image. A failure degrades image caching only;
  // boot continues (a black window is strictly worse).
  await _safeInit('desktop_db', DesktopDatabase.initialize);
  await _safeInit('mediakit', () async => MediaKit.ensureInitialized());
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await _safeInit('window_manager', windowManager.ensureInitialized);
    await _safeInit('window_service', WindowService.instance.initialize);
  }
  // P0/P1: platform-aware in-memory image caps. Phones share RAM with the
  // OS — 200 entries / 150MB; desktops keep 500 / 300MB. Every remote
  // image must ALSO pass memCacheWidth via DizzyImage so full-res files
  // can never inflate into 8-30MB decoded bitmaps (the 30-40min slow leak).
  final isMobile = Platform.isAndroid || Platform.isIOS;
  PaintingBinding.instance.imageCache.maximumSize = isMobile ? 200 : 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      (isMobile ? 150 : 300) << 20;
  // P0/P9: global resource governor (RAM/CPU/GPU sampler) starts with the
  // app, not just the player — 30-40min browse+watch soak needs it live.
  // Drives PerformanceMode (ambient/glass/buffer shedding) on breach.
  ResourceGovernor.instance.start();
  PerformanceMode.isLowRamDevice = isMobile && await _isLowRamPhone();
  PerformanceMode.detectDeviceTier(isMobile: isMobile);
  // P17 / UX3: Smooth Mode & Low-End Mode defaults ON for ≤3GB-RAM phones.
  SharedPreferences? prefs;
  await _safeInit('prefs', () async {
    prefs = await SharedPreferences.getInstance();
  });
  final lowEndSaved = prefs?.getBool('perf_low_end_device_mode');
  if (lowEndSaved ?? PerformanceMode.isLowRamDevice) {
    PerformanceMode.setLowEndDeviceMode(true);
  } else {
    final smoothSaved = prefs?.getBool('perf_smooth_mode');
    PerformanceMode.setSmoothMode(
      smoothSaved ?? PerformanceMode.isLowRamDevice,
    );
  }
  // Edge-to-edge draws under transparent system bars; bar colors AND icon
  // brightness are owned per-frame by the AnnotatedRegion in [DizzyApp], so
  // no bootstrap overlay style here (it would be stale on theme toggle).
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
  await _safeInit('env', EnvService.initialize);
  await _safeInit('player_settings', PlayerSettings.initialize);
  // WP-P0: device code first — cloud install upsert needs it.
  await _safeInit('device_id', DeviceIdService.initialize);
  // S2 (v1.1.9): cloud LAST + non-blocking — never delays startup.
  // v1.2.0-ADMIN: after auth, pull remote config + announcements (cached, soft).
  // Phase 3: identity boot registers this device (devices table was 0 rows
  // because init() was never called). All cloud writes stay fail-soft.
  // ignore: unawaited_futures
  CloudClient.init().then((_) => CloudAuthService.init()).then((_) async {
    // ignore: unawaited_futures
    DizzyIdentityService.init();
    // v1.3.3-T1.3: restore saved phone badge state.
    // ignore: unawaited_futures
    PhoneLinkService.init();
    // v1.3.3-T1.1: reload saved @username (local cache, then cloud refresh).
    // ignore: unawaited_futures
    DizzySocialService.loadCurrentUsername();
    // v1.3.3: first-run gate needs server truth as early as possible.
    // ignore: unawaited_futures
    UsernameGateState.ensureResolved();
    // v1.3.3 Phase 2: drain any personalisation events queued offline.
    // ignore: unawaited_futures
    TasteEventService.ensureLoaded().then((_) => TasteEventService.flush());
    // v1.3.3 Phase 3: FCM wiring + token registration (phones only, and
    // only after the user granted notifications).
    // ignore: unawaited_futures
    PushService.initialize();
    var appVersion = 'unknown';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    RemoteConfigService.initialize();
    AnnouncementService.initialize(appVersion: appVersion);
    // v1.3.3-T4: offline FAQ bundle (tier 1 support answers, zero network).
    unawaited(SupportAgentService.initialize());
    // v1.2.0-T2.2: opted-in error queue flush (no-op when consent OFF).
    AppErrorLog.schedulePeriodicFlush();
    AppErrorLog.flushOnStart();
  });
  // IPTV controller reads IptvSettings.defaultScrapeSource during init
  // (iptv_controller.dart:161) — settings must land first or the source is
  // always the fallback.
  await _safeInit('iptv_settings', IptvSettings.initialize);
  await Future.wait([
    _safeInit('addons', () => AddonManager.instance.initialize()),
    _safeInit('adult_gate', () => AdultSectionGate.ensureLoaded()),
    _safeInit('app_theme', () => AppThemeService.initialize()),
    _safeInit('audiobook_settings', () => AudiobookSettings.initialize()),
    _safeInit('continue_watching', () => ContinueWatchingService.initialize()),
    _safeInit('continue_reading', () => ContinueReadingService.initialize()),
    _safeInit('reader_settings', () => ReaderSettings.initialize()),
    _safeInit('dock_settings', () => DockSettings.initialize()),
    _safeInit('glass_settings', () => GlassSettings.initialize()),
    _safeInit('home_page_settings', () => HomePageSettings.initialize()),
    _safeInit('dub_mode', () => DubModeService.initialize()),
    _safeInit('iptv_controller', () => IptvController.instance.init()),
    _safeInit('manga_settings', () => MangaSettings.initialize()),
    _safeInit('music_settings', () => MusicSettings.initialize()),
    _safeInit('music_download', () => MusicDownloadService.instance.init()),
    _safeInit('qobuz', () => QobuzMusicService.instance.initialize()),
    _safeInit('my_list', () => MyListService.initialize()),
    _safeInit('p2p_settings', () => P2pSettingsService.initialize()),
    _safeInit('download_service', () => DownloadService.instance.initialize()),
    _safeInit('discord_rpc', () => DiscordRpcService.instance.initialize()),
    _safeInit('dizzy_profile', () => DizzyProfileService.initialize()),
    _safeInit(
      'scraper_quarantine',
      () => ScraperQuarantineService.initialize(),
    ),
  ]);
  // v1.2.0-P3: guest follow lifecycle (auto-open host titles anywhere).
  PartySession.onGuestStart = GuestFollowService.arm;
  PartySession.onSessionEnd = () {
    // ignore: unawaited_futures
    GuestFollowService.disarm();
  };
  // UX5: video<->music conflict resolution (one sound at a time).
  GlobalMediaCoordinator.instance.attach();
  runApp(const DizzyApp());
}

/// P0/P17: true on phones with ≤3GB total RAM (Android /proc/meminfo;
/// iOS unknown → false, Smooth Mode stays opt-in there).
Future<bool> _isLowRamPhone() async {
  try {
    if (Platform.isAndroid) {
      final lines = await File('/proc/meminfo').readAsLines();
      for (final l in lines) {
        if (l.startsWith('MemTotal:')) {
          final kb = int.tryParse(l.split(RegExp(r'\s+'))[1]);
          if (kb != null) return kb <= 3 * 1024 * 1024;
        }
      }
    }
  } catch (_) {}
  return false;
}

/// P8: app-background suspend — Discord RPC, updater checks, cloud polls
/// and downloads pause when the app hides; voice (LiveKit) is EXCLUDED
/// by design and keeps running until room exit (user decision).
class _PerfLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      DownloadService.instance.pauseForNetworkLoss();
      DiscordRpcService.instance.clearToIdle();
      // Background timers have no user to serve: stop the process samplers
      // (PowerShell/nvidia-smi spawns), presence beats, outbox retries and
      // the OEM keep-alive tick. Voice/party are deliberately untouched.
      ResourceGovernor.instance.pause();
      NotificationTriggers.pause();
      HeartbeatService.instance.stop();
      DmOutbox.stopScheduler();
      // Personalisation queue drains before the process loses the network.
      unawaited(TasteEventService.flush());
      _DizzyAppState._markAliveTimer?.cancel();
      _DizzyAppState._markAliveTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      DownloadService.instance.resumeAfterNetworkReturn();
      ResourceGovernor.instance.resume();
      NotificationTriggers.resume();
      unawaited(TasteEventService.flush());
      unawaited(HeartbeatService.instance.start());
      DmOutbox.startScheduler(_DizzyAppState._sendOutboxEntry);
      _DizzyAppState._ensureMarkAliveTimer();
    }
  }
}

final _perfLifecycleObserver = _PerfLifecycleObserver();

/// P6 — desktop drag: mouse + trackpad se rails drag ho (touch jaisa).
/// Bina iske desktop pe horizontal ListView sirf wheel/arrows se chalta.
class DesktopCustomScrollBehavior extends MaterialScrollBehavior {
  const DesktopCustomScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class DizzyApp extends StatefulWidget {
  const DizzyApp({super.key});

  @override
  State<DizzyApp> createState() => _DizzyAppState();
}

class _DizzyAppState extends State<DizzyApp> with WidgetsBindingObserver {
  static bool _hasCheckedInitialUpdate = false;
  static bool _isShowingUpdateDialog = false;
  static Timer? _markAliveTimer;
  bool _revokedShown = false;
  bool _updateBlockedShown = false;

  // Resume herd guard: focus changes can emit several `resumed` events in a
  // burst; one debounced pass per burst, and no two passes inside 30s.
  Timer? _resumeDebounce;
  DateTime? _lastResumeAt;
  bool _resumeBusy = false;

  /// Phase K4: app came back to the foreground → flush the DM outbox now
  /// instead of waiting for the scheduler tick (poll-on-resume).
  /// Phase P: an instant forced heartbeat so dashboard "Active now" flips
  /// the moment the app opens — `force` bypasses the client throttle (the
  /// server still no-ops identical beats inside 60s). On `paused` nothing
  /// is sent: the beat timers are suspended with the app (see
  /// [_PerfLifecycleObserver]) and resume with it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleResumeWork();
      return;
    }
    if (state != AppLifecycleState.paused) return;
    // Phase K3: background VIDEO does not stay — decoding a hidden player
    // is pure heat. Audio does stay: voice owns its own foreground service
    // and music has its own session, and neither is touched here. An active
    // party timeline is left alone too, because pausing locally would
    // desync everyone else in the room.
    if (!PartySession.instance.inParty &&
        GlobalMediaCoordinator.instance.videoActive.value) {
      final pauseVideo = GlobalMediaCoordinator.instance.onPauseVideoRequest;
      pauseVideo?.call();
    }
  }

  void _scheduleResumeWork() {
    if (_resumeDebounce != null) return;
    _resumeDebounce = Timer(const Duration(milliseconds: 350), () {
      _resumeDebounce = null;
      unawaited(_resumeWork());
    });
  }

  Future<void> _resumeWork() async {
    if (_resumeBusy) return;
    final now = DateTime.now();
    final last = _lastResumeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastResumeAt = now;
    _resumeBusy = true;
    try {
      await Future.wait([
        _soft(DmOutbox.flush(send: _sendOutboxEntry)),
        _soft(AnnouncementService.refresh()),
        _soft(HeartbeatService.instance.beat(force: true)),
        // v1.3.3-T5: hot-fix pull rides the resume heartbeat (forced,
        // TTL-bypassed).
        _soft(RemoteConfigService.refresh(force: true)),
        // v1.3.3 Phase 3: a token registered while offline retries here;
        // already-registered tokens are a no-op.
        _soft(PushService.registerToken()),
      ]);
    } finally {
      _resumeBusy = false;
    }
  }

  /// Resume refreshes are best-effort — one unreachable service must not
  /// cancel the others in the herd.
  static Future<void> _soft(Future<dynamic> task) async {
    try {
      await task;
    } catch (_) {}
  }

  static Future<bool> _sendOutboxEntry(OutboxEntry e) =>
      DizzySocialService.sendDirectMessage(
        recipientUid: e.recipientUid,
        body: e.body,
      );

  /// Phase K4: outbox is the only part of this that can lose data, so it
  /// is loaded and scheduled before anything else at boot.
  Future<void> _bootOutbox() async {
    await DmOutbox.load();
    DmOutbox.startScheduler(_sendOutboxEntry);
    _ensureMarkAliveTimer();
    unawaited(OemKillDetector.markAlive());
    final suggest = await OemKillDetector.considerBoot(
      pendingCount: DmOutbox.entries.value.length,
    );
    if (!suggest || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showBatteryGuide();
    });
  }

  /// One 1-minute keep-alive ticker for the process — created once and
  /// reused across restarts, cancelled while backgrounded / disposed.
  static void _ensureMarkAliveTimer() {
    _markAliveTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(OemKillDetector.markAlive());
    });
  }

  /// Easy English only: no "OEM", no "whitelist", no technical words.
  void _showBatteryGuide() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Some messages did not send'),
        content: const Text(
          'It looks like your phone stopped Dizzy while it was still '
          'sending. Let Dizzy keep running in the background and your '
          'messages will always get through.\n\n'
          'You can turn this on in the next screen — pick Battery, then '
          'choose "No restrictions" or "Unrestricted".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              unawaited(openBatterySettings());
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  Future<void> openBatterySettings() async {
    // package: opens this app's own system page — Battery, permissions and
    // "no restrictions" all live one tap away, on every OEM, without the
    // app needing a battery-optimization permission it cannot justify.
    try {
      final uri = Uri.parse('package:com.sirius6907.dizzyv3');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // P8: background-suspend observer (never touches voice).
    WidgetsBinding.instance.addObserver(_perfLifecycleObserver);
    // Phase C: revoked device → notice screen (once, when boot reports it).
    DizzyIdentityService.deviceRevoked.addListener(_onDeviceRevoked);
    // Phase D: full-ban gate (boot refresh, fail-soft offline).
    BanService.state.addListener(_onBanChanged);
    // Phase E1: blocking force-update when the server deadline has passed.
    RemoteConfigService.revision.addListener(_enforceForceUpdate);
    // Phase I3: rehydrate the staged-update state machine (a process killed
    // mid-download must not leave the Hub row stuck).
    UpdateOrchestrator.restore();
    // Phase J1/J2: notification channels + event triggers (downloads,
    // announcements, staged updates) feeding the Hub Notification Center.
    unawaited(NotificationTriggers.attach());
    // Phase K4: resend whatever a kill left in the DM outbox, and ask the
    // battery guide once if that kill looks like an OEM freezer.
    unawaited(_bootOutbox());
    // Phase K3: voice gets its own foreground service so the mic thread
    // survives the screen going off.
    unawaited(VoiceBackgroundGate.attach());
    // Phase L2: fleet presence + coarse activity (consent-gated; consent
    // OFF means no beats at all and only boot-time last_seen ages).
    unawaited(HeartbeatService.instance.start());
    // Phase K1: a system media session (now-playing notification, lock
    // screen / Bluetooth controls) follows the music player. No-ops off
    // Android, so desktop and web behaviour is untouched. The watcher is an
    // app-wide singleton — a restart must not add a second 1 Hz ticker.
    unawaited(MusicMediaSessionWatcher.instance.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedInitialUpdate) {
        _hasCheckedInitialUpdate = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _checkForUpdates();
        });
      }
      // Boot may have finished before this listener attached.
      _onDeviceRevoked();
      BanService.refresh().then((_) => _onBanChanged());
      _enforceForceUpdate();
      // Phase J1: one Easy-English permission ask, ever.
      unawaited(_maybeAskNotificationPermission());
      // v1.3.3 Phase 3: a notification tap that arrived before the navigator
      // existed (cold start) opens now.
      PushService.openPendingTap();
    });
  }

  /// Phase J1 — Android 13+ POST_NOTIFICATIONS, asked once with a plain
  /// explanation and a real "Not now" (never a blocking prompt).
  Future<void> _maybeAskNotificationPermission() async {
    try {
      await NotificationService.initialize();
      if (!mounted || NotificationService.permissionAsked) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final go = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('Stay in the loop?'),
          content: const Text(
            'Dizzy can tell you when a new movie or show lands, when a '
            'download finishes, or when an update is ready. No spam — and '
            'you can change this any time in Profile → Notifications.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (go == true) {
        await NotificationService.requestPermission();
        // v1.3.3 Phase 3: only now may an FCM token be registered.
        unawaited(PushService.onPermissionGranted());
      } else {
        await NotificationService.markPermissionAsked();
      }
    } catch (e) {
      debugPrint('[Notify] permission prompt failed (soft): $e');
    }
  }

  void _onDeviceRevoked() {
    if (!DizzyIdentityService.deviceRevoked.value) return;
    if (_revokedShown) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _revokedShown = true;
    Navigator.of(ctx).pushReplacement(
      MaterialPageRoute(builder: (_) => const DeviceRevokedScreen()),
    );
  }

  void _onBanChanged() {
    if (!BanService.state.value.blocksEverything) return;
    if (_revokedShown) return; // revoked screen wins if both fired
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _revokedShown = true;
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const BanNoticeScreen()));
  }

  /// Phase E1 — blocking screen ONLY when remote config carried a deadline
  /// that has passed (UpdateGate). Offline / no config → never fires.
  Future<void> _enforceForceUpdate() async {
    if (_updateBlockedShown) return;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final gate = UpdateGate.evaluate(
        currentVersion: pkg.version,
        minVersion: RemoteConfigService.minAppVersion,
        forceAfter: RemoteConfigService.forceAfter,
        now: DateTime.now(),
      );
      if (!gate.isBlocking) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _updateBlockedShown = true;
      Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (_) => UpdateRequiredScreen(minVersion: gate.minVersion),
        ),
      );
    } catch (e) {
      debugPrint('Force-update gate failed (soft): $e');
    }
  }

  @override
  void dispose() {
    _resumeDebounce?.cancel();
    _resumeDebounce = null;
    _markAliveTimer?.cancel();
    _markAliveTimer = null;
    unawaited(MusicMediaSessionWatcher.instance.stop());
    RemoteConfigService.revision.removeListener(_enforceForceUpdate);
    BanService.state.removeListener(_onBanChanged);
    DizzyIdentityService.deviceRevoked.removeListener(_onDeviceRevoked);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeObserver(_perfLifecycleObserver);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_isShowingUpdateDialog) return;
    try {
      final updateInfo = await UpdateOrchestrator.autoStageIfDue();
      if (updateInfo == null) return;

      // I2: a silent staged download is already running (or finished) — the
      // Hub's Install-now pill is the UI, no modal needed.
      final runState = UpdateStateMachine.state.value;
      if (runState == UpdateRunState.downloading ||
          runState == UpdateRunState.ready) {
        debugPrint('[Main] Update staged silently — skipping modal.');
        return;
      }

      BuildContext? context = navigatorKey.currentContext;
      for (int i = 0; i < 6 && (context == null || !context.mounted); i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        context = navigatorKey.currentContext;
      }

      if (context != null && context.mounted && !_isShowingUpdateDialog) {
        _isShowingUpdateDialog = true;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
        _isShowingUpdateDialog = false;
      }
    } catch (e) {
      _isShowingUpdateDialog = false;
      debugPrint('Error checking for app updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppThemeService.currentThemeId,
      builder: (context, themeId, _) {
        final palette = AppThemeService.palettes.firstWhere(
          (candidate) => candidate.id == themeId,
          orElse: () => AppThemeService.currentPalette.value,
        );
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Dizzy',
          debugShowCheckedModeBanner: false,
          // v1.3.3-T2.3: coarse route breadcrumbs for the crash trail.
          navigatorObservers: [TrailNavigatorObserver()],
          theme: AppThemeService.createThemeData(palette),
          scrollBehavior: const DesktopCustomScrollBehavior().copyWith(
            overscroll: false,
          ),
          // Polish P12: 200% font safety rail — layouts never break,
          // TalkBack + focus order untouched.
          // UX1: Universal Spotlight Search via Ctrl+K / Cmd+K
          builder: (context, child) => ValueListenableBuilder<AppThemePalette>(
            valueListenable: AppThemeService.currentPalette,
            builder: (context, palette, _) {
              final isLight = palette.isLight;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isLight
                      ? Brightness.dark
                      : Brightness.light,
                  // iOS reports the opposite of the icon brightness.
                  statusBarBrightness: isLight
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarIconBrightness: isLight
                      ? Brightness.dark
                      : Brightness.light,
                ),
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed) &&
                        event.logicalKey == LogicalKeyboardKey.keyK) {
                      final currentCtx = navigatorKey.currentContext;
                      if (currentCtx != null) {
                        UniversalSpotlightModal.show(currentCtx);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: DizzyA11y.kMaxTextScale,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
