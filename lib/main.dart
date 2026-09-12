import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:media_kit/media_kit.dart';

import 'package:window_manager/window_manager.dart';

import './pages/home/home_page.dart';
import './services/addon/addon_manager.dart';
import './services/theme/app_theme_service.dart';
import './services/updater/app_updater_service.dart';
import './services/books/continue_reading_service.dart';
import './services/books/reader_settings.dart';
import './services/continue_watching/continue_watching_service.dart';
import './services/theme/custom_background_service.dart';
import './services/theme/dock_settings.dart';
import './services/theme/glass_settings.dart';
import './services/player/dub_mode_service.dart';
import './services/cloud/announcement_service.dart';
import './services/cloud/cloud_client.dart';
import './services/cloud/cloud_auth_service.dart';
import './services/cloud/remote_config_service.dart';
import './services/device/device_id_service.dart';
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
import './services/config/env_service.dart';
import './services/window/window_service.dart';
import './services/p2p/p2p_settings_service.dart';
import './services/discord/discord_rpc_service.dart';
import './widgets/updater/update_dialog.dart';
import './core/error_boundary.dart';
import './core/nav_key.dart';
import './services/watchparty/party_session.dart';
import './services/watchparty/guest_auto_open.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await WindowService.instance.initialize();
  }
  // Cap the in-memory image cache: 500 entries / 300 MB decoded bitmaps max.
  // Posters are decoded at capped sizes (memCacheWidth) so RAM stays bounded.
  PaintingBinding.instance.imageCache.maximumSize = 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 300 << 20;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await EnvService.initialize();
  await PlayerSettings.initialize();
  // WP-P0: device code first — cloud install upsert needs it.
  await DeviceIdService.initialize();
  // S2 (v1.1.9): cloud LAST + non-blocking — never delays startup.
  // v1.2.0-ADMIN: after auth, pull remote config + announcements (cached, soft).
  // ignore: unawaited_futures
  CloudClient.init().then((_) => CloudAuthService.init()).then((_) {
    RemoteConfigService.initialize();
    AnnouncementService.initialize(appVersion: '1.2.0');
    // v1.2.0-T2.2: opted-in error queue flush (no-op when consent OFF).
    AppErrorLog.schedulePeriodicFlush();
    AppErrorLog.flushOnStart();
  });
  await Future.wait([
    AddonManager.instance.initialize(),
    AppThemeService.initialize(),
    AudiobookSettings.initialize(),
    ContinueWatchingService.initialize(),
    ContinueReadingService.initialize(),
    ReaderSettings.initialize(),
    CustomBackgroundService.initialize(),
    DockSettings.initialize(),
    GlassSettings.initialize(),
    HomePageSettings.initialize(),
    DubModeService.initialize(),
    IptvController.instance.init(),
    IptvSettings.initialize(),
    MangaSettings.initialize(),
    MusicSettings.initialize(),
    MusicDownloadService.instance.init(),
    QobuzMusicService.instance.initialize(),
    MyListService.initialize(),
    P2pSettingsService.initialize(),
    DownloadService.instance.initialize(),
    DiscordRpcService.instance.initialize(),
    DizzyProfileService.initialize(),
    ScraperQuarantineService.initialize(),
  ]);
  // v1.2.0-P3: guest follow lifecycle (auto-open host titles anywhere).
  PartySession.onGuestStart = GuestFollowService.arm;
  PartySession.onSessionEnd = () {
    // ignore: unawaited_futures
    GuestFollowService.disarm();
  };
  // v1.2.0-T3.2: global error boundary — branded screen, never white-screen.
  installGlobalErrorHandlers(restartApp: () => runApp(const DizzyApp()));
  runApp(const DizzyApp());
}

class DizzyApp extends StatefulWidget {
  const DizzyApp({super.key});

  @override
  State<DizzyApp> createState() => _DizzyAppState();
}

class _DizzyAppState extends State<DizzyApp>
    with WidgetsBindingObserver {
  static bool _hasCheckedInitialUpdate = false;
  static bool _isShowingUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedInitialUpdate) {
        _hasCheckedInitialUpdate = true;
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _checkForUpdates();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_isShowingUpdateDialog) return;
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo == null) return;

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
    return ValueListenableBuilder<AppThemePalette>(
      valueListenable: AppThemeService.currentPalette,
      builder: (context, palette, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Dizzy',
          debugShowCheckedModeBanner: false,
          theme: AppThemeService.createThemeData(palette),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            overscroll: false,
          ),
          // Polish P12: 200% font safety rail — layouts never break,
          // TalkBack + focus order untouched.
          builder: (context, child) =>
              MediaQuery.withClampedTextScaling(
            maxScaleFactor: DizzyA11y.kMaxTextScale,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

