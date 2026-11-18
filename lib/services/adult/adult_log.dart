/// Log hygiene for the 18+ extractors.
///
/// Debug logs are the one place an adult URL can escape the device (logcat,
/// crash reporters, screen shares). These helpers keep the diagnostic value
/// — which host failed — without printing paths, slugs or query tokens.
abstract final class AdultLog {
  /// `scheme://host/…` — never the path, query or fragment.
  static String redactUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return '<empty>';
    final uri = Uri.tryParse(raw);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '<hidden>';
    final scheme = (uri!.scheme.isEmpty) ? 'url' : uri.scheme;
    return '$scheme://$host/…';
  }

  /// Error text with the URL stripped: most HTTP exceptions append
  /// `, uri = https://…`, so only the type is safe to print.
  static String redactError(Object error) => error.runtimeType.toString();
}
