import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PHASE 37 — Supabase RLS Policy Hardening.
///
/// Task table names map to the real schema:
///   user_profiles  → profiles
///   rooms          → rooms
///   room_members   → room_members
///   messages       → room_messages (+ dm_messages)
///   friend_requests→ friendships
///
/// The test concatenates [supabase/schema_v119.sql] with every file in
/// [supabase/migrations/] and asserts the five required guarantees
/// statically (no live Supabase needed).
String _loadAllSql() {
  final buf = StringBuffer();
  final schema = File('supabase/schema_v119.sql');
  if (schema.existsSync()) buf.writeln(schema.readAsStringSync());
  final dir = Directory('supabase/migrations');
  if (dir.existsSync()) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      buf.writeln('\n-- ==== ${f.path} ====');
      buf.writeln(f.readAsStringSync());
    }
  }
  return buf.toString();
}

/// All `create policy ... on <table>` statement bodies (lowercased).
Map<String, List<String>> _policiesByTable(String sql) {
  final out = <String, List<String>>{};
  final re = RegExp(
    r'create\s+policy\s+"[^"]+"\s+on\s+([\w.]+)\s+for\s+(\w+)(.*?);',
    caseSensitive: false,
    dotAll: true,
  );
  for (final m in re.allMatches(sql)) {
    final table = m.group(1)!.split('.').last.toLowerCase();
    final stmt = 'for ${m.group(2)} ${m.group(3)}'.toLowerCase();
    out.putIfAbsent(table, () => []).add(stmt);
  }
  return out;
}

void main() {
  late String sql;
  late Map<String, List<String>> policies;

  setUpAll(() {
    sql = _loadAllSql();
    expect(sql, isNotEmpty, reason: 'Supabase SQL must exist.');
    policies = _policiesByTable(sql);
  });

  group('Phase37 RLS policy hardening', () {
    test('1. User can read own profile but not others', () {
      final stmts = policies['profiles'] ?? [];
      expect(stmts, isNotEmpty,
          reason: 'profiles table must have RLS policies.');
      final readable = stmts
          .where((s) => s.contains('for select') || s.contains('for all'))
          .toList();
      expect(readable, isNotEmpty,
          reason: 'profiles must have a SELECT (or FOR ALL) policy.');
      expect(
        readable.any((s) => s.contains('auth.uid() = user_id')),
        isTrue,
        reason: 'profiles read must be scoped to auth.uid() = user_id.',
      );
    });

    test('2. User can only update own profile', () {
      final stmts = policies['profiles'] ?? [];
      final writable = stmts
          .where((s) =>
              s.contains('for update') ||
              s.contains('for all') ||
              s.contains('for insert'))
          .toList();
      expect(writable, isNotEmpty,
          reason: 'profiles must have a write policy.');
      for (final s in writable) {
        expect(s.contains('auth.uid() = user_id'), isTrue,
            reason: 'profiles write must be scoped to owner: $s');
      }
    });

    test('3. Room membership is required to read/write room data', () {
      // rooms: members/host/public-only visibility.
      final rooms = policies['rooms'] ?? [];
      expect(rooms, isNotEmpty, reason: 'rooms must have RLS policies.');
      final roomReads = rooms
          .where((s) => s.contains('for select') || s.contains('for all'))
          .toList();
      expect(roomReads, isNotEmpty);
      expect(
        roomReads.any((s) =>
            s.contains('room_members') ||
            s.contains("visibility = 'public'") ||
            s.contains('host_user_id')),
        isTrue,
        reason: 'rooms read must gate on membership/host/public.',
      );
      // room_messages: members (+host) only.
      final chat = policies['room_messages'] ?? [];
      expect(chat, isNotEmpty,
          reason: 'room_messages must have RLS policies.');
      expect(
        chat.any((s) => s.contains('room_members')),
        isTrue,
        reason: 'room_messages read must require room_members membership.',
      );
      // Writes go through membership-checked RPCs, never open inserts.
      final lower = sql.toLowerCase();
      expect(lower, contains('send_room_message'));
      expect(lower, contains('join_watch_room'));
      // No direct open INSERT policy on room_messages / room_members.
      final memberInserts = (policies['room_members'] ?? [])
          .where((s) => s.contains('for insert'))
          .toList();
      for (final s in memberInserts) {
        expect(s.contains('auth.uid()'), isTrue,
            reason: 'room_members insert must be auth-scoped: $s');
      }
      final chatInserts = (chat)
          .where((s) => s.contains('for insert'))
          .toList();
      expect(chatInserts, isEmpty,
          reason:
              'room_messages must have NO direct INSERT policy (writes via send_room_message RPC).');
    });

    test('4. Friend request can only be sent to valid users', () {
      final stmts = policies['friendships'] ?? [];
      expect(stmts, isNotEmpty,
          reason: 'friendships table must have RLS policies.');
      final inserts = stmts.where((s) => s.contains('for insert')).toList();
      expect(inserts, isNotEmpty,
          reason: 'friendships must have an INSERT policy.');
      expect(
        inserts.any((s) =>
            s.contains('auth.uid() = requester_id') &&
            s.contains('requester_id <> addressee_id')),
        isTrue,
        reason:
            'friendship INSERT must require requester = auth.uid() and forbid self-friend.',
      );
      // Reads limited to the two parties.
      final reads = stmts
          .where((s) => s.contains('for select') || s.contains('for all'))
          .toList();
      expect(
        reads.any((s) =>
            s.contains('requester_id') && s.contains('addressee_id')),
        isTrue,
        reason: 'friendship reads must be limited to involved parties.',
      );
    });

    test('5. Unauthenticated users cannot access protected data', () {
      const protected = [
        'profiles',
        'rooms',
        'room_members',
        'room_messages',
        'friendships',
        'dm_messages',
        'dm_threads',
        'devices',
        'identities',
        'cloud_backups',
        'cloud_sessions',
      ];
      for (final table in protected) {
        final stmts = policies[table] ?? [];
        expect(stmts, isNotEmpty,
            reason: '$table must have at least one RLS policy.');
        for (final s in stmts) {
          // No policy may grant the public/anon role without an auth.uid()
          // check — every protected statement must be identity-scoped.
          final grantsOpenRole =
              s.contains('to public') || s.contains('to anon');
          if (grantsOpenRole) {
            expect(s.contains('auth.uid()'), isTrue,
                reason: '$table policy grants anon/public without auth check: $s');
          } else {
            expect(
              s.contains('to authenticated') || s.contains('auth.uid()'),
              isTrue,
              reason: '$table policy must target authenticated users: $s',
            );
          }
          expect(s.contains('using (true)'), isFalse,
              reason: '$table must not contain open USING (true): $s');
          expect(s.contains('with check (true)'), isFalse,
              reason: '$table must not contain open WITH CHECK (true): $s');
        }
      }
      // Every protected table must have RLS enabled.
      final lower = sql.toLowerCase();
      for (final table in protected) {
        expect(
          lower.contains('alter table') &&
              lower.contains('enable row level security'),
          isTrue,
        );
        final rlsRe = RegExp(
          r'alter\s+table\s+(public\.)?' + table + r'\s+enable\s+row\s+level\s+security',
          caseSensitive: false,
        );
        expect(rlsRe.hasMatch(sql), isTrue,
            reason: '$table must have RLS enabled.');
      }
    });
  });
}
