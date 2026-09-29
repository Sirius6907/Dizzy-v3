import 'dart:math' as math;

/// One attempt's outcome, as far as the retry layer is concerned.
///
/// The policy never inspects a body or a message — only this. That keeps
/// the decision free-text-free, which matters because these strings are
/// the only thing that leaves this file.
enum NetAttempt {
  /// A usable response came back (2xx or 3xx). Never retried.
  success,

  /// A response came back but the status is worth another go:
  /// 408, 429, and every 5xx. Retried up to the policy's budget.
  retryableStatus,

  /// No response at all — socket error, DNS failure, timeout.
  /// Always retried (subject to budget).
  transportError,

  /// A response came back and it is a definitive refusal: 400, 401, 403,
  /// 404, 409, 422 and friends. Retrying cannot change the answer, so it
  /// is never retried — but the host is demonstrably alive, so it does
  /// not count toward the circuit breaker's failure streak.
  terminalStatus,
}

/// P3 — retry + exponential backoff + jitter, as pure data.
///
/// Everything here is a pure function or a value so the policy can be
/// unit-tested without a socket, a clock, or a random source. [delayFor]
/// takes all three as arguments; production passes the real ones.
class RetryPolicy {
  /// Total attempts, including the first one. `1` means "never retry".
  final int maxAttempts;

  /// First backoff step. Every later step multiplies by [backoffFactor].
  final Duration baseDelay;

  /// Backoff multiplier. 2.0 gives 400ms → 800ms → 1600ms.
  final double backoffFactor;

  /// Upper bound on a single backoff step, so a long chain cannot
  /// produce a multi-minute sleep on a phone that just came back online.
  final Duration maxDelay;

  /// Full-jitter ceiling as a fraction of the computed step. 0.2 means
  /// the actual wait lands in `[step * 0.8, step]`.
  ///
  /// Jitter is a *fraction of the step*, not a fixed window, so a short
  /// retry is not turned into a long one by the jitter alone.
  final double jitterRatio;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 8),
    this.jitterRatio = 0.2,
  })  : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
        assert(backoffFactor >= 1.0),
        assert(jitterRatio >= 0.0 && jitterRatio <= 1.0);

  /// A policy that never retries. Used where a retry is worse than a
  /// failure — a POST that creates a torrent, for instance.
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  /// Fail fast. For interactive calls the user is watching a spinner.
  static const RetryPolicy quick = RetryPolicy(
    maxAttempts: 2,
    baseDelay: Duration(milliseconds: 250),
  );

  /// Background work where a slow answer is better than no answer.
  static const RetryPolicy patient = RetryPolicy(
    maxAttempts: 4,
    baseDelay: Duration(milliseconds: 600),
    maxDelay: Duration(seconds: 10),
  );

  /// Whether a given attempt outcome earns another attempt.
  ///
  /// A [NetAttempt.terminalStatus] is never retried: the server answered,
  /// and the answer will not change because we asked again.
  bool shouldRetry(NetAttempt outcome, int attempt) {
    if (outcome == NetAttempt.success) return false;
    if (outcome == NetAttempt.terminalStatus) return false;
    return attempt < maxAttempts;
  }

  /// Whether a failure of this outcome should count toward the
  /// per-host circuit breaker.
  ///
  /// A 404 is not evidence the host is unhealthy, so it must not open
  /// the breaker — otherwise browsing a catalogue with a few dead
  /// entries would take the whole host offline.
  static bool countsTowardBreaker(NetAttempt outcome) =>
      outcome == NetAttempt.transportError ||
      outcome == NetAttempt.retryableStatus;

  /// Map an HTTP status onto an attempt outcome.
  ///
  /// 2xx and 3xx succeed. 408 (request timeout), 429 (rate limited) and
  /// every 5xx are worth another go. Everything else in 4xx is final.
  static NetAttempt classifyStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 400) return NetAttempt.success;
    if (statusCode == 408 || statusCode == 429) {
      return NetAttempt.retryableStatus;
    }
    if (statusCode >= 500) return NetAttempt.retryableStatus;
    if (statusCode >= 400) return NetAttempt.terminalStatus;
    // A 1xx or a nonsense code never reaches a real client, but if one
    // does, treat it as final rather than as a host failure.
    return NetAttempt.terminalStatus;
  }

  /// Backoff before attempt number `attempt` (1-based; the value for
  /// attempt 1 is [baseDelay] with jitter).
  ///
  /// Pure: [random] is injected so a test can pin the jitter to 0.0 or
  /// 1.0 and assert the exact wait.
  Duration delayFor(int attempt, {required double random}) {
    if (attempt < 1) return Duration.zero;
    // Cap the exponent before pow() so a large maxAttempts cannot
    // overflow to infinity and then to NaN on the way back.
    final exponent = math.min(attempt - 1, 32);
    final scaled = baseDelay.inMicroseconds *
        math.pow(backoffFactor, exponent).toDouble();
    final capped = math.min(scaled, maxDelay.inMicroseconds.toDouble());
    final jitterSpan = capped * jitterRatio;
    // random is expected in [0,1); clamp so a misbehaving source cannot
    // produce a negative Duration.
    final unit = random.clamp(0.0, 1.0);
    final wait = capped - (jitterSpan * unit);
    return Duration(microseconds: wait.round().clamp(0, maxDelay.inMicroseconds));
  }

  @override
  String toString() => 'RetryPolicy(attempts: $maxAttempts, '
      'base: ${baseDelay.inMilliseconds}ms, x$backoffFactor)';
}
