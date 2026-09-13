import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class MusicMiniPipService {
  MusicMiniPipService._();
  static final MusicMiniPipService instance = MusicMiniPipService._();

  final ValueNotifier<bool> isMiniPipMode = ValueNotifier<bool>(false);

  Size? _savedSize;
  Offset? _savedPosition;

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> enterMiniPip() async {
    if (isMiniPipMode.value) return;

    if (isDesktop) {
      try {
        _savedSize = await windowManager.getSize();
        _savedPosition = await windowManager.getPosition();

        await windowManager.setMinimumSize(const Size(320, 120));
        await windowManager.setSize(const Size(350, 135));
        await windowManager.setAlwaysOnTop(true);
      } catch (e) {
        debugPrint('[MusicMiniPipService] Desktop window enter error: $e');
      }
    }

    isMiniPipMode.value = true;
  }

  Future<void> exitMiniPip() async {
    if (!isMiniPipMode.value) return;

    if (isDesktop) {
      try {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setMinimumSize(const Size(800, 600));

        if (_savedSize != null) {
          await windowManager.setSize(_savedSize!);
        } else {
          await windowManager.setSize(const Size(1280, 800));
        }

        if (_savedPosition != null) {
          await windowManager.setPosition(_savedPosition!);
        }
      } catch (e) {
        debugPrint('[MusicMiniPipService] Desktop window exit error: $e');
      }
    }

    isMiniPipMode.value = false;
  }

  Future<void> toggleMiniPip() async {
    if (isMiniPipMode.value) {
      await exitMiniPip();
    } else {
      await enterMiniPip();
    }
  }
}
