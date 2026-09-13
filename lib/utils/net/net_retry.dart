import 'dart:async';
import 'dart:math';

/// P10 — bounded retry with exponential backoff + jitter for every
/// network probe / scrape / metadata fetch in Dizzy.
///
/// Rules (hard):
/// - max 3 attempts, delays 1s → 2s → 4s (+0-25% jitter)
/// - only transient failures retry (SocketException, TimeoutException,
///   HTTP 429 / 5xx). 4xx (except 429) never retries.
/// - total added latency per call is capped at ~7s so a dead source can
///   never stall the probe race's 4s drain deadline from the outside.
class NetRetry {
  const NetRetry._();

  static const int maxAttempts = 3;
  static const List<int> backoffMs = [1000, 2000, 4000];

  /// Returns true when [error] / [statusCode] is worth one more attempt.
  static bool shouldRetry(Object error, {int? statusCode}) {
    if (statusCode != null) {
      if (statusCode == 429) return true;
      if (statusCode >= 500 && statusCode < 600) return true;
      return false;
    }
    final name = error.runtimeType.toString();
    return name.contains('Socket') ||
        name.contains('Timeout') ||
        name.contains('Handshake') ||
        name.contains('Connection') ||
        name.contains('Http') ||
        name.contains('Network') ||
        name.contains('ClientException');
  }

  /// Runs [task] with bounded retries. Rethrows the last error.
  static Future<T> run<T>(Future<T> Function() task) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await task();
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts - 1 || !shouldRetry(e)) rethrow;
        final jitter =
            (backoffMs[attempt] * Random().nextDouble() * 0.25).toInt();
        await Future.delayed(
            Duration(milliseconds: backoffMs[attempt] + jitter));
      }
    }
    throw lastError ?? StateError('NetRetry exhausted without error');
  }
}
