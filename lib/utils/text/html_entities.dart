/// HTML-entity unescaping for provider-supplied text (Part A, 2026-11-12).
///
/// Music providers escape some fields at the source: JioSaavn upstream
/// returns artist names like `Vishal &amp; Shekhar`, so the app displayed
/// raw `&amp;` in mix titles and artist chips. Every client boundary that
/// builds user-facing strings from provider JSON applies [unescapeHtmlEntities]
/// once, here — never per-widget, so the fix is one pure function with one
/// test suite.
///
/// Covers the entities that actually occur in music metadata (ampersand,
/// quotes, angle brackets, nbsp) plus decimal and hex numeric references.
/// Unknown or malformed references are passed through untouched, and the
/// function is idempotent-safe: real text that merely *contains* the word
/// "amp" is never touched.
String unescapeHtmlEntities(String input) {
  if (input.isEmpty || !input.contains('&')) return input;

  final result = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (ch != '&') {
      result.write(ch);
      i++;
      continue;
    }

    // Find the terminating ';' within a bounded window (entities are short).
    final semi = input.indexOf(';', i + 1);
    if (semi == -1 || semi - i > 10 || semi == i + 1) {
      result.write(ch);
      i++;
      continue;
    }

    final body = input.substring(i + 1, semi);
    final replacement = _decodeEntity(body);
    if (replacement != null) {
      result.write(replacement);
      i = semi + 1;
    } else {
      result.write(ch);
      i++;
    }
  }
  return result.toString();
}

String? _decodeEntity(String body) {
  // Decimal: &#39; / Hex: &#x27; / &#X27;
  if (body.startsWith('#')) {
    final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
    final digits = hex ? body.substring(2) : body.substring(1);
    if (digits.isEmpty || digits.length > 7) return null;
    final code = int.tryParse(digits, radix: hex ? 16 : 10);
    if (code == null || code < 0 || code > 0x10FFFF) return null;
    return String.fromCharCode(code);
  }
  return _namedEntities[body];
}

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};
