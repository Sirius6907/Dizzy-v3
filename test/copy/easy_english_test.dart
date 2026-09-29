import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PHASE 38 — Easy English Universal Sweep.
///
/// Scans every `.dart` file under `lib/` for tech jargon in *user-facing*
/// strings. Code comments, imports and internal identifiers are ignored:
/// only string literals on lines that render UI (Text, SnackBar, hintText,
/// dialogs, …) or surface errors to the user (throw Exception/StateError,
/// onProgress error, _showSnack) are checked.
///
/// Forbidden → Easy English:
///   authentication → login | authorization → permission | endpoint → connection
///   payload → data | API → access key / connection | token → key
///   cache invalidation → clear old data | middleware → controller
///   deprecated → outdated
const _forbidden = <String, String>{
  'authentication': 'login',
  'authorization': 'permission',
  'endpoint': 'connection',
  'payload': 'data',
  'api': 'access key / connection',
  'token': 'key',
  'cache invalidation': 'clear old data',
  'middleware': 'controller',
  'deprecated': 'outdated',
};

final _uiMarker = RegExp(
  r'Text\s*\(|SelectableText|RichText|Tooltip|SnackBar|hintText|labelText|'
  r'helperText|errorText|title\s*:|subtitle\s*:|content\s*:|label\s*:|'
  r'message|_showSnack|showDialog|AlertDialog|onProgress|throw\s+Exception|'
  r'throw\s+StateError',
);
/// Extracts single/double-quoted literal bodies from [line] (no regex,
/// so no quoting pitfalls). Handles backslash escapes; ignores the
/// opposite quote type inside a literal.
List<String> _literals(String line) {
  final out = <String>[];
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == '"' || c == "'") {
      final buf = StringBuffer();
      i++;
      while (i < line.length && line[i] != c) {
        if (line[i] == '\\' && i + 1 < line.length) {
          buf.write(line[i + 1]);
          i += 2;
        } else {
          buf.write(line[i]);
          i++;
        }
      }
      out.add(buf.toString());
      if (i < line.length) i++; // skip closing quote
    } else {
      i++;
    }
  }
  return out;
}
final _wordPatterns = {
  for (final w in _forbidden.keys) w: RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false),
};

String _stripComments(String src) {
  final lines = src.split('\n');
  final out = <String>[];
  var inBlock = false;
  for (final line in lines) {
    var l = line;
    if (inBlock) {
      final end = l.indexOf('*/');
      if (end == -1) continue;
      l = l.substring(end + 2);
      inBlock = false;
    }
    // Remove block comments starting/ending on this line (naive but enough).
    l = l.replaceAll(RegExp(r'/\*.*?\*/'), '');
    final start = l.indexOf('/*');
    if (start != -1) {
      l = l.substring(0, start);
      inBlock = true;
    }
    final lineComment = l.indexOf('//');
    // Keep `https://` / `http://` intact: only cut `//` not preceded by `:`.
    if (lineComment != -1 && (lineComment == 0 || l[lineComment - 1] != ':')) {
      l = l.substring(0, lineComment);
    }
    out.add(l);
  }
  return out.join('\n');
}

bool _isCodeLiteral(String s) {
  if (s.trim().length < 3) return true;
  final t = s.trim();
  if (t.startsWith('package:') ||
      t.contains('.dart') ||
      t.contains('http://') ||
      t.contains('https://') ||
      t.contains('Bearer ') ||
      t.startsWith('lib/') ||
      t.startsWith('assets/')) {
    return true;
  }
  return false;
}

void main() {
  test('no forbidden tech jargon in user-facing strings', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist.');
    final violations = <String>[];
    final files = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(files, isNotEmpty);
    for (final file in files) {
      final code = _stripComments(file.readAsStringSync());
      final lines = code.split('\n');
      // UI calls often span lines (`_showSnack(` on one line, the message
      // 1-2 lines below). A marker line that does NOT end its statement
      // (no trailing `;`) opens a continuation: following lines stay
      // user-facing until the statement closes (`;`).
      var continuation = 0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        if (trimmed.startsWith('import ') ||
            trimmed.startsWith('export ') ||
            trimmed.startsWith('part ')) {
          continuation = 0;
          continue;
        }
        final hasMarker = _uiMarker.hasMatch(line);
        final userFacing = hasMarker || continuation > 0;
        if (hasMarker &&
            !trimmed.endsWith(';') &&
            !trimmed.endsWith('{') &&
            !trimmed.endsWith('}')) {
          continuation = 6; // multi-line UI call: cover following lines
        } else if (trimmed.contains(';')) {
          continuation = 0;
        } else if (continuation > 0) {
          continuation--;
        }
        if (!userFacing) continue;
        for (final s in _literals(line)) {
          if (_isCodeLiteral(s)) continue;
          for (final entry in _wordPatterns.entries) {
            if (entry.value.hasMatch(s)) {
              violations.add(
                              '${file.path}:${i + 1} [${entry.key} → use "${_forbidden[entry.key]}"] '
                              '"${s.length > 90 ? '${s.substring(0, 90)}…' : s}"',
                            );
              break;
            }
          }
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'Easy English violations:\n${violations.join('\n')}');
  });
}
