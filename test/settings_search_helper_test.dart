import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dizzy/services/settings/settings_search_helper.dart';

SettingSearchEntry _e(String title,
        {String subtitle = '', String keywords = ''}) =>
    SettingSearchEntry(
      title: title,
      subtitle: subtitle,
      keywords: keywords,
      icon: Icons.settings,
      open: (_) => const SizedBox(),
    );

/// Polish P8: in-settings search never loses a setting.
void main() {
  group('SettingsSearchHelper', () {
    test('empty query matches everything', () {
      final e = _e('Video & Upscaling');
      expect(SettingsSearchHelper.matches('', e), isTrue);
      expect(SettingsSearchHelper.matches('   ', e), isTrue);
    });

    test('matches title case-insensitively', () {
      final e = _e('Privacy & Account');
      expect(SettingsSearchHelper.matches('privacy', e), isTrue);
      expect(SettingsSearchHelper.matches('PRIVACY', e), isTrue);
    });

    test('matches subtitle + keywords', () {
      final e = _e('Sources',
          subtitle: 'Which video sources work now', keywords: 'scraper');
      expect(SettingsSearchHelper.matches('video', e), isTrue);
      expect(SettingsSearchHelper.matches('scraper', e), isTrue);
    });

    test('multi-word query needs every word', () {
      final e = _e('Debrid & Cloud Streaming', keywords: 'real torbox');
      expect(SettingsSearchHelper.matches('cloud debrid', e), isTrue);
      expect(SettingsSearchHelper.matches('cloud trakt', e), isFalse);
    });

    test('filter keeps only hits', () {
      final entries = [_e('Video'), _e('Trakt.tv Sync'), _e('Simkl Sync')];
      final hits = SettingsSearchHelper.filter('sync', entries);
      expect(hits.map((e) => e.title), ['Trakt.tv Sync', 'Simkl Sync']);
    });
  });
}
