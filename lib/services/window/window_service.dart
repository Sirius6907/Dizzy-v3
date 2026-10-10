import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../music/music_player_controller.dart';
import '../stream/torrent_stream_service.dart';
import '../system/resource_governor.dart';

/// Centralized window and fullscreen state manager for desktop and mobile.
class WindowService with WindowListener {
  static final WindowService instance = WindowService._internal();
  WindowService._internal();

  final ValueNotifier<bool> isFullscreenNotifier = ValueNotifier<bool>(false);
  bool _isTransitioning = false;

  bool get isFullscreen => isFullscreenNotifier.value;
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> initialize() async {
    if (!isDesktop) return;
    try {
      windowManager.addListener(this);
      // Intercept the native close signal so onWindowClose runs the
      // heavy-native teardown (music/torrents/timers) before destroy.
      // Without this, close hides the window but orphans the processes.
      await windowManager.setPreventClose(true);
      final isFs = await windowManager.isFullScreen();
      isFullscreenNotifier.value = isFs;
    } catch (e) {
      debugPrint('[WindowService] initialize error: $e');
    }
  }

  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
    }
  }

  /// Executes true borderless OS fullscreen toggle covering the Windows taskbar.
  Future<void> toggleFullscreen() async {
    if (_isTransitioning) return;
    _isTransitioning = true;

    try {
      if (!isDesktop) {
        // Mobile fallback
        final next = !isFullscreenNotifier.value;
        isFullscreenNotifier.value = next;
        if (next) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
        return;
      }

      final isCurrentlyFs = await windowManager.isFullScreen();
      if (isCurrentlyFs || isFullscreenNotifier.value) {
        await windowManager.setFullScreen(false);
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
        isFullscreenNotifier.value = false;
      } else {
        // Crucial for Windows: unmaximize first to drop the 8px DWM resize frame
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
        await windowManager.setFullScreen(true);
        isFullscreenNotifier.value = true;
      }
    } catch (e) {
      debugPrint('[WindowService] toggleFullscreen error: $e');
    } finally {
      _isTransitioning = false;
    }
  }

  /// Alias for toggleFullscreen
  Future<void> toggleFullScreen() => toggleFullscreen();

  /// Forces exit from fullscreen (e.g. when leaving player screen).
  Future<void> exitFullscreen() async {
    if (!isDesktop) {
      if (isFullscreenNotifier.value) {
        isFullscreenNotifier.value = false;
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      return;
    }
    if (_isTransitioning) return;
    _isTransitioning = true;
    try {
      final isCurrentlyFs = await windowManager.isFullScreen();
      if (isCurrentlyFs || isFullscreenNotifier.value) {
        await windowManager.setFullScreen(false);
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
        isFullscreenNotifier.value = false;
      }
    } catch (e) {
      debugPrint('[WindowService] exitFullscreen error: $e');
    } finally {
      _isTransitioning = false;
    }
  }

  // ── WindowListener Callbacks (Synchronize OS events) ──

  @override
  void onWindowEnterFullScreen() {
    isFullscreenNotifier.value = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    isFullscreenNotifier.value = false;
  }

  @override
  void onWindowRestore() {
    windowManager.isFullScreen().then((isFs) {
      isFullscreenNotifier.value = isFs;
    });
  }

  @override
  void onWindowUnmaximize() {
    windowManager.isFullScreen().then((isFs) {
      isFullscreenNotifier.value = isFs;
    });
  }

  @override
  void onWindowMaximize() {
    windowManager.isFullScreen().then((isFs) {
      isFullscreenNotifier.value = isFs;
    });
  }

  // ── Close-to-quit (2026-10-10) ─────────────────────────────────
  //
  // Without this, closing the window hides the UI but leaves the Dart
  // isolate + TorrServer subprocess + mpv + timers alive as orphans
  // (user-visible as dizzy.exe / torrserver.exe still in Task Manager).
  // We intercept the close, tear down the heavy natives, then let the
  // OS destroy the window (SetQuitOnClose(true) quits the loop).

  @override
  void onWindowClose() async {
    await shutdownForQuit();
    try {
      await windowManager.destroy();
    } catch (_) {
      try {
        await windowManager.close();
      } catch (_) {}
    }
  }

  /// Best-effort teardown of everything that survives a hidden window:
  /// music + torrent engine + governor timers. Never throws — quit
  /// must proceed even if one service is already half-dead.
  static Future<void> shutdownForQuit() async {
    try {
      await MusicPlayerController.instance.pause();
    } catch (_) {}
    try {
      await TorrentStreamService().stop();
    } catch (_) {}
    try {
      ResourceGovernor.instance.dispose();
    } catch (_) {}
    try {
      windowManager.removeListener(WindowService.instance);
    } catch (_) {}
  }
}
