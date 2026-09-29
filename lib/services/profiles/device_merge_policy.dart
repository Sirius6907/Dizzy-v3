/// F3 — "naya phone, sab wapas" in one idea: a short code that carries an
/// old anonymous session into a new device.
///
/// Everything here is pure, because this is the part a user trusts with
/// their history. The rules:
///
///  * The merge is a UNION. Nothing is ever overwritten, so a wrong code
///    cannot cost you a list you had on the old phone.
///  * It is idempotent. Running it twice changes nothing the second time —
///    a person who taps the button again gets the same answer, not a
///    doubled library.
///  * A short code is short on purpose: 6 characters, no look-alike
///    letters, so it can be read out loud on a phone call without
///    spelling ("oh, that's a zero? or an O?").
///
/// The server half (devices, friendships, progress rows) is the
/// `merge_devices` edge function; this file is the client half and the
/// shared shape of the answer.
library;

/// Answer shape returned by both halves of the merge. Counts are real
/// numbers the user sees — never a vague "done".
class DeviceMergeResult {
  /// Titles that came back on the new phone.
  final int watchlistAdded;

  /// Watched items that came back.
  final int historyAdded;

  /// People who came back.
  final int friendsAdded;

  /// Resume points that came back.
  final int progressAdded;

  /// Rows the other device was ahead on (progress advanced).
  final int progressAdvanced;

  /// True when this call changed nothing — the second tap, or a repeat
  /// of a code already used.
  final bool alreadyMerged;

  const DeviceMergeResult({
    this.watchlistAdded = 0,
    this.historyAdded = 0,
    this.friendsAdded = 0,
    this.progressAdded = 0,
    this.progressAdvanced = 0,
    this.alreadyMerged = false,
  });

  /// Everything that came back, for the one-line summary.
  int get totalAdded =>
      watchlistAdded + historyAdded + friendsAdded + progressAdded;

  /// The Easy English line shown when the merge lands.
  String get summaryLine {
    if (alreadyMerged) return 'This code was already used. Nothing changed.';
    if (totalAdded == 0) return 'No new titles found for this code.';
    final n = totalAdded;
    return n == 1 ? '1 thing came back with you.' : '$n things came back with you.';
  }

  Map<String, dynamic> toJson() => {
        'watchlistAdded': watchlistAdded,
        'historyAdded': historyAdded,
        'friendsAdded': friendsAdded,
        'progressAdded': progressAdded,
        'progressAdvanced': progressAdvanced,
        'alreadyMerged': alreadyMerged,
      };
}

/// The merge rules. Everything is a set operation — no overwrites.
abstract final class DeviceMergePolicy {
  /// Short code length. Long enough to be worth a code, short enough to
  /// read out loud.
  static const int codeLength = 6;

  /// Letters and digits that look like something else when read aloud
  /// (0/O, 1/I/L, 5/S, 8/B, 2/Z) are never in a code.
  static const String alphabet = '34679ACDEFGHJKMNPQRTUVWXY';

  /// How long a code stays usable. Long enough to walk to another room,
  /// short enough that a shoulder-surfer cannot use it tomorrow.
  static const Duration codeTtl = Duration(minutes: 15);

  /// True when [raw] is a code we could have issued.
  static bool isValidCode(String raw) {
    final c = raw.trim().toUpperCase();
    if (c.length != codeLength) return false;
    for (final ch in c.split('')) {
      if (!alphabet.contains(ch)) return false;
    }
    return true;
  }

  /// Clean a typed or pasted code: upper-case it and drop the separators
  /// people add while copying (`ab cd-ef`).
  ///
  /// We deliberately do NOT "helpfully" swap O→0, B→8, S→5 and friends.
  /// Both halves of every look-alike pair are excluded from [alphabet], so
  /// any such swap would map a real character onto an invalid one. A
  /// mistyped letter is caught by [isValidCode] and the person retypes it —
  /// which is honest, and it is one tap on a keyboard.
  static String normalizeCode(String raw) {
    final upper = raw.trim().toUpperCase();
    final out = StringBuffer();
    for (final ch in upper.split('')) {
      if (ch == ' ' || ch == '-' || ch == '_') continue;
      out.write(ch);
    }
    return out.toString();
  }

  /// Make a code from random-ish bytes. Deterministic for a given [seed]
  /// so tests do not need a real RNG.
  static String codeFromSeed(int seed) {
    final buf = StringBuffer();
    var v = seed.abs();
    for (var i = 0; i < codeLength; i++) {
      if (v == 0) v = 0x9E3779B1;
      v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
      buf.write(alphabet[v % alphabet.length]);
    }
    final code = buf.toString();
    return isValidCode(code) ? code : codeFromSeed(seed + 7);
  }

  /// True when a code issued at [issuedAt] is still good.
  static bool isFresh(DateTime issuedAt, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    return ref.difference(issuedAt) < codeTtl && !ref.isBefore(issuedAt);
  }

  /// Union of two string sets — the whole "never overwrite" promise.
  ///
  /// A plain set union is idempotent on its own: running it twice returns
  /// the same set, and nothing from the first pass is lost on the second.
  static Set<String> union(Set<String> a, Set<String> b) => {...a, ...b};

  /// Merge a remote copy of a keyed map into the local one.
  ///
  /// Keys only ever get added. A key on both sides keeps the local value —
  /// the new device may have fresher data, and the old one is archived
  /// rather than discarded.
  ///
  /// Returns the merged map and how many keys came back.
  static (Map<String, String>, int) mergeMaps(
    Map<String, String> local,
    Map<String, String> remote,
  ) {
    final out = Map<String, String>.from(local);
    var gained = 0;
    for (final e in remote.entries) {
      if (e.key.isEmpty) continue;
      if (out.containsKey(e.key)) continue;
      out[e.key] = e.value;
      gained++;
    }
    return (out, gained);
  }

  /// Turn a server answer into a [DeviceMergeResult].
  ///
  /// `true` when the server told us the code was already spent, which is
  /// how the user gets an honest "nothing changed" instead of a second
  /// merge that silently re-adds everything.
  static DeviceMergeResult fromServer(Map<String, dynamic> json) {
    int n(String k) {
      final v = json[k];
      if (v is int) return v < 0 ? 0 : v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return DeviceMergeResult(
      watchlistAdded: n('watchlist_added'),
      historyAdded: n('history_added'),
      friendsAdded: n('friends_added'),
      progressAdded: n('progress_added'),
      progressAdvanced: n('progress_advanced'),
      alreadyMerged: json['already_merged'] == true,
    );
  }
}
