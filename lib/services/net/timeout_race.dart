import 'dart:async';

/// Race [pending] against [timeout] with an explicit timer instead of
/// [Future.timeout].
///
/// `Future.timeout`'s `onTimeout` is checked against the receiver's
/// *runtime* type argument, not the static one. A future whose body only
/// throws is inferred `Future<Never>`, so the runtime rejects a value
/// callback with a TypeError before a single listener is attached: the
/// timeout machinery never runs, and the pending error escapes to the
/// zone as an unhandled error even though the caller's `catch` does run.
/// Both handlers are attached here, synchronously, so a throwing future
/// is always contained by the caller's catch — and the timer is cancelled
/// the moment [pending] settles, so no request leaves a stray timer.
Future<T> raceTimeout<T>(
  Future<T> pending,
  Duration timeout,
  T Function() onTimeout,
) {
  final completer = Completer<T>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(onTimeout());
    }
  });
  pending.then<void>(
    (res) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(res);
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}
