/// Source probe — a single player screen, built as its own Windows exe.
///
/// Build:
///   flutter build windows --release -t tool/player_probe/main.dart
///
/// Why a separate entrypoint instead of a debug switch in the app: the probe
/// must answer one question only — "does THIS scraper give a playable video
/// for THIS TMDB id?" — so it deliberately has no home, no race, no failover
/// chain. It reuses the shipped scrapers, [PlayerSettings] and media_kit, so
/// what it reports is the app's real behaviour.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'package:dizzy/rust/frb_generated.dart';
import 'package:dizzy/services/config/env_service.dart';
import 'package:dizzy/services/player/player_settings.dart';

import 'probe_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Same order as the app's boot: native player first, then env keys, then
  // player settings. Each stage is soft — a probe that cannot read .env or
  // prefs should still open and say so, never sit on a black window.
  MediaKit.ensureInitialized();
  await _softInit('env', EnvService.initialize);
  await _softInit('player_settings', PlayerSettings.initialize);

  // The Rust adblock engine for embed playback. Soft: if the DLL cannot be
  // found the webview still plays, it just cannot block ads — and the log
  // says exactly that so the tester is never guessing.
  if (Platform.isWindows) {
    await _softInit('adblock_bridge', () async {
      await _ensureAdblockDllNextToExe();
      await RustLib.init();
    });
  }

  // The title comes from the shared Windows runner, so the probe would show up
  // as a second window called "Dizzy" and the tester could not tell which one
  // is the probe while comparing behaviour side by side.
  if (Platform.isWindows) {
    await _softInit('window_title', () async {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('Dizzy · Source Probe');
    });
  }

  runApp(const ProbeApp());
}

Future<void> _softInit(String name, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e, st) {
    debugPrint('[probe] $name init failed: $e');
    debugPrint('[probe] $name stack: $st');
  }
}

/// The rust bridge loader looks for `dizzy_adblock.dll` next to the exe, or
/// relative to the current directory (`rust/dizzy_adblock/target/release/`).
/// When the probe exe is launched straight from its build folder by a
/// double-click, cwd is the exe folder and neither place has it — so copy it
/// there once, from wherever the repo put it. Idempotent and silent on any
/// failure (the engine init reports the consequence itself).
Future<void> _ensureAdblockDllNextToExe() async {
  final exe = Platform.resolvedExecutable;
  final cut = exe.lastIndexOf(Platform.pathSeparator);
  final exeDir = cut > 0 ? exe.substring(0, cut) : Directory.current.path;
  final target = File('$exeDir${Platform.pathSeparator}dizzy_adblock.dll');
  if (await target.exists()) return;

  // Search order mirrors the loader: cwd first (flutter run / CLI launch),
  // then walking up from the exe, because `build/windows/x64/runner/Release`
  // sits inside the repo that owns `rust/`.
  final candidates = <File>[
    File('rust${Platform.pathSeparator}dizzy_adblock${Platform.pathSeparator}'
        'target${Platform.pathSeparator}release${Platform.pathSeparator}'
        'dizzy_adblock.dll'),
  ];
  var dir = Directory(exeDir);
  for (var depth = 0; depth < 6; depth++) {
    candidates.add(
      File('${dir.path}${Platform.pathSeparator}rust${Platform.pathSeparator}'
          'dizzy_adblock${Platform.pathSeparator}target${Platform.pathSeparator}'
          'release${Platform.pathSeparator}dizzy_adblock.dll'),
    );
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  for (final candidate in candidates) {
    if (!await candidate.exists()) continue;
    try {
      await candidate.copy(target.path);
      debugPrint('[probe] adblock dll placed: ${target.path}');
      return;
    } catch (e) {
      debugPrint('[probe] adblock dll copy failed (soft): $e');
      return;
    }
  }
  debugPrint('[probe] adblock dll not found — embeds will play unblocked');
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF0E0E11);
    return MaterialApp(
      title: 'Dizzy · Source Probe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
          brightness: Brightness.dark,
          surface: surface,
        ),
        scaffoldBackgroundColor: surface,
        fontFamily: 'Segoe UI',
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF1A1A22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
      home: const ProbeScreen(),
    );
  }
}
