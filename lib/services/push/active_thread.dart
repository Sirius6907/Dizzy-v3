/// v1.4 item 5 — which chat is on screen right now.
///
/// A push for the thread you are already reading should land in the Center
/// silently: a banner over the message you just received is noise. Two lines
/// of state, no I/O, nothing to fail.
class ActiveThread {
  ActiveThread._();

  static String? _key;

  /// The [PushRoute.threadKey] of the open chat, or null.
  static String? get key => _key;

  /// Called from the chat page's `initState`.
  static void enter(String? key) {
    final k = (key ?? '').trim();
    _key = k.isEmpty ? null : k;
  }

  /// Called from `dispose`. Ignores a stale leave so a page pushed on top of
  /// another one cannot clear the wrong thread.
  static void leave(String? key) {
    final k = (key ?? '').trim();
    if (k.isEmpty) return;
    if (_key == k) _key = null;
  }

  /// True when [key] is the chat currently open.
  static bool isOpen(String? key) {
    final k = (key ?? '').trim();
    return k.isNotEmpty && k == _key;
  }

  static void resetForTest() => _key = null;
}
