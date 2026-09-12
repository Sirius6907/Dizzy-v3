import 'package:flutter/material.dart';

import '../../design/dizzy_tokens.dart';
import '../../services/settings/settings_search_helper.dart';
import '../stats/stats_page.dart';
import 'about_settings_page.dart';
import 'addons_settings_page.dart';
import 'appearance_settings_page.dart';
import 'debrid_settings_page.dart';
import 'privacy_settings_page.dart';
import 'profiles_settings_page.dart';
import 'scraper_health_page.dart';
import 'simkl_settings_page.dart';
import 'trakt_settings_page.dart';
import 'updates_settings_page.dart';
import 'video_settings_page.dart';
import 'watch_party_page.dart';

/// Polish P8 — find any setting in ≤3 taps (Easy English, non-tech).
///
/// Search icon (AppBar) → type → tap result opens the page directly.
class SettingsSearchDelegate extends SearchDelegate<WidgetBuilder?> {
  SettingsSearchDelegate()
      : super(
          searchFieldLabel: 'Find a setting…',
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
        );

  static final List<SettingSearchEntry> _entries = [
    SettingSearchEntry(
      title: 'Appearance & Interface',
      subtitle: 'Themes, colors, Home look',
      keywords: 'theme glass dark light color look display',
      icon: Icons.palette_rounded,
      open: (_) => const AppearanceSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Video & Upscaling',
      subtitle: 'Quality, Anime4K, playback',
      keywords: 'video quality anime4k upscaling player shader gpu',
      icon: Icons.auto_awesome_rounded,
      open: (_) => const VideoSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'My Dizzy Wrap',
      subtitle: 'Watch time, streaks, top genres',
      keywords: 'wrap stats year watch time streak genre',
      icon: Icons.emoji_events_rounded,
      open: (_) => const StatsPage(),
    ),
    SettingSearchEntry(
      title: 'Privacy & Account',
      subtitle: 'Sync, consent, delete cloud data',
      keywords: 'privacy account sync consent delete cloud data',
      icon: Icons.privacy_tip_rounded,
      open: (_) => const PrivacySettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Profiles',
      subtitle: 'Private profiles, PIN, kids mode',
      keywords: 'profile pin kids child family user',
      icon: Icons.people_alt_rounded,
      open: (_) => const ProfilesSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Watch Party',
      subtitle: 'Watch together with friends',
      keywords: 'party together friends room watch sync',
      icon: Icons.groups_rounded,
      open: (_) => const WatchPartyPage(),
    ),
    SettingSearchEntry(
      title: 'Sources',
      subtitle: 'Which video sources work now',
      keywords: 'sources health status scraper working',
      icon: Icons.rss_feed_rounded,
      open: (_) => const ScraperHealthPage(),
    ),
    SettingSearchEntry(
      title: 'Debrid & Cloud Streaming',
      subtitle: 'Real-Debrid, TorBox, Premiumize',
      keywords: 'debrid real torbox premiumize cloud torrent',
      icon: Icons.cloud_download_rounded,
      open: (_) => const DebridSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Addons',
      subtitle: 'Catalogs and content providers',
      keywords: 'addon catalog provider stremio install',
      icon: Icons.extension_rounded,
      open: (_) => const AddonsSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Trakt.tv Sync',
      subtitle: 'Watchlist and history sync',
      keywords: 'trakt watchlist history sync',
      icon: Icons.movie_filter_rounded,
      open: (_) => const TraktSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'Simkl Sync',
      subtitle: 'Movies, TV and anime sync',
      keywords: 'simkl sync anime list',
      icon: Icons.tv_rounded,
      open: (_) => const SimklSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'App Updates',
      subtitle: 'Latest version and patches',
      keywords: 'update version upgrade patch',
      icon: Icons.system_update_rounded,
      open: (_) => const UpdatesSettingsPage(),
    ),
    SettingSearchEntry(
      title: 'About Dizzy',
      subtitle: 'Version, engine, credits',
      keywords: 'about version credits info help',
      icon: Icons.info_outline_rounded,
      open: (_) => const AboutSettingsPage(),
    ),
  ];

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white38),
      ),
    );
  }

  void _open(BuildContext context, SettingSearchEntry e) {
    close(context, null);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => e.open(ctx)),
    );
  }

  Widget _resultsList(BuildContext context, List<SettingSearchEntry> hits) {
    if (hits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DizzySpace.lg),
          child: Text(
            'No setting found.\nTry a shorter word — like “video” or “sync”.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: DizzyType.body,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(DizzySpace.md),
      itemCount: hits.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: DizzySpace.xs),
      itemBuilder: (ctx, i) {
        final e = hits[i];
        return Semantics(
          button: true,
          label: 'Open ${e.title}',
          child: ListTile(
            leading: Icon(e.icon, color: Colors.white70),
            title: Text(
              e.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: DizzyType.body,
                fontWeight: DizzyType.wSemiBold,
              ),
            ),
            subtitle: Text(
              e.subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: DizzyType.caption,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: DizzyRadius.mdAll,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            tileColor: const Color(0xFF12151E),
            onTap: () => _open(context, e),
          ),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) =>
      _resultsList(context, SettingsSearchHelper.filter(query, _entries));

  @override
  Widget buildResults(BuildContext context) =>
      _resultsList(context, SettingsSearchHelper.filter(query, _entries));

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );
}
