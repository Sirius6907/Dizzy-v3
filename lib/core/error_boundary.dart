import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/errors/app_error_log.dart';

/// v1.2.0-T3.2: global error boundary + branded crash screen.
///
/// Install once in main() before runApp:
/// - Framework/build errors → friendly screen (never white-screen).
/// - Async errors outside widgets → logged, app keeps running.
/// - Reporting is consent-gated inside AppErrorLog (crash toggle OFF = local only).
/// - Restart button re-runs the app closure passed from main.
void installGlobalErrorHandlers({required void Function() restartApp}) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: unawaited_futures
    AppErrorLog.log(
      code: 'E_FLUTTER',
      screen: 'global',
      detail: '${details.exception}'.replaceAll(RegExp(r'\s+'), ' '),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[GlobalError] $error');
    // ignore: unawaited_futures
    AppErrorLog.log(
      code: 'E_ASYNC',
      screen: 'global',
      detail: '$error'.replaceAll(RegExp(r'\s+'), ' '),
    );
    return true; // handled — keep the app alive
  };

  ErrorWidget.builder = (details) => ErrorScreen(
        message: 'Something went wrong here.',
        onRestart: restartApp,
      );
}

/// Branded fallback shown instead of the red/white error screen.
/// Easy English only. Report = consent-gated queue. Restart = fresh runApp.
class ErrorScreen extends StatelessWidget {
  final String message;
  final void Function() onRestart;

  const ErrorScreen({
    super.key,
    required this.message,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF080A0F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('😟', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text(
                'Oops! This part crashed.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      // ignore: unawaited_futures
                      AppErrorLog.log(
                        code: 'E_USER_REPORT',
                        screen: 'error_screen',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thanks! Report saved.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Report'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFF),
                    ),
                    onPressed: onRestart,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Restart'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
