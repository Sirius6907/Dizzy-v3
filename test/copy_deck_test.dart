import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/download/download_error_text.dart';
import 'package:dizzy/services/profiles/kids_mode.dart';
import 'package:dizzy/services/stats/wrap_copy.dart';
import 'package:dizzy/widgets/common/state_view.dart';
import 'package:dizzy/widgets/guide/guide_card.dart';

/// Polish P20 — copy deck gate: Easy English everywhere, tech never leaks.
///
/// Banned: exception names, E_* codes, stack traces, null-speak.
/// Any new user-facing line lands in the pools below.
void main() {
  const banned = [
    'exception',
    'stacktrace',
    'stack trace',
    'nullptr',
    'nullpointer',
    'e_net_',
    'e_http_',
    'e_hls_',
    'e_p2p_',
    'e_debrid_',
    'e_space_',
    'e_file_',
    'e_unknown',
    'socketexception',
    'timeoutexception',
    'httpexception',
    'formatexception',
  ];

  List<String> deck() {
    final lines = <String>[];
    // P7: every guide card of every feature, straight from the content map
    // so a new guide can never slip past this gate.
    for (final entry in AppGuides.byKey.entries) {
      for (final s in entry.value) {
        lines.add('${entry.key}: ${s.title}');
        lines.add('${entry.key}: ${s.line}');
      }
    }
    // Retired 4-card party flow, still linked from copy-deck callers.
    for (final s in AppGuides.watchParty) {
      lines.add(s.title);
      lines.add(s.line);
    }
    // Download errors: every code.
    for (final c in [
      'E_NET_TIMEOUT',
      'E_HTTP_401_403',
      'E_HTTP_404_410',
      'E_HTTP_416_RANGE',
      'E_HTTP_5XX',
      'E_SPACE_FULL',
      'E_FILE_GONE',
      'E_P2P_ENGINE',
      'E_DEBRID_RESOLVE',
      'E_HLS_PARSE',
      'E_UNKNOWN',
    ]) {
      lines.add(DownloadErrorText.easyText(c));
    }
    // Generic states over nasty raws.
    for (final raw in [
      'SocketException: boom',
      'TimeoutException after 0:00:10',
      'Http 403 forbidden',
      'Http 404 gone',
      'RangeError (index): E_UNKNOWN null',
      null,
    ]) {
      lines.add(StateViewCopy.friendlyError(raw));
    }
    // Profiles + Wrap.
    lines.add(KidsMode.subtitle(isKids: true, hasPin: true));
    lines.add(KidsMode.hello('Ashu', isKids: true));
    lines.add(WrapCopy.hoursCheer(0));
    lines.add(WrapCopy.hoursCheer(5000));
    lines.add(WrapCopy.streakLine(7));
    lines.add(WrapCopy.emptyTaste());
    // P6: music search empty state (DizzyStateView line).
    lines.add('Try another song, artist or album name.');
    // P6: narrow-compact bar labels.
    lines.add('Taste Quiz');
    lines.add('Go back');
    return lines;
  }

  group('Copy deck (P20)', () {
    test('every line non-empty and short', () {
      for (final l in deck()) {
        expect(l.trim(), isNotEmpty);
        expect(l.length, lessThanOrEqualTo(120),
            reason: 'too long: $l');
      }
    });

    test('no banned tech words anywhere', () {
      for (final l in deck()) {
        final low = l.toLowerCase();
        for (final b in banned) {
          expect(low.contains(b), isFalse,
              reason: '"$b" leaked in: "$l"');
        }
      }
    });
  });
}
