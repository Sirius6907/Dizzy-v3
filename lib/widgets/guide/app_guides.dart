import 'guide_step.dart';

/// P7 — every intro card Dizzy can show, in Easy English.
///
/// House rules for every line in this file:
///  * no tech words (no "stream", "source", "API", "token", "cache");
///  * one line = one job, and it stays under a screen's worth of text;
///  * at most 3 cards per feature — longer tours get skipped, and skipping
///    must be the easy way out.
class AppGuides {
  AppGuides._();

  // ── Home ────────────────────────────────────────────────────────────────
  static const home = [
    GuideStep(
      icon: '🏠',
      title: 'Your home screen',
      line: 'Every kind of show lives here, in rows.',
    ),
    GuideStep(
      icon: '🔍',
      title: 'Find anything fast',
      line: 'Tap search and type a few letters.',
    ),
    GuideStep(
      icon: '👆',
      title: 'Swipe sideways',
      line: 'Slide a row to see more of it.',
    ),
  ];

  // ── Spotlight / universal search ────────────────────────────────────────
  static const spotlight = [
    GuideStep(
      icon: '⚡',
      title: 'One search for everything',
      line: 'Movies, shows, songs, books — all here.',
    ),
    GuideStep(
      icon: '⌨️',
      title: 'Search from anywhere',
      line: 'Press the search key on your keyboard.',
    ),
  ];

  // ── Movies & shows ─────────────────────────────────────────────────────
  static const movie = [
    GuideStep(
      icon: '🎬',
      title: 'Find a movie',
      line: 'Tap a poster to see the full page.',
    ),
    GuideStep(
      icon: '▶️',
      title: 'Play in one tap',
      line: 'Press play. It starts right away.',
    ),
    GuideStep(
      icon: '❤️',
      title: 'Keep what you like',
      line: 'Tap the heart to save it for later.',
    ),
  ];

  // ── Anime ──────────────────────────────────────────────────────────────
  static const anime = [
    GuideStep(
      icon: '🌸',
      title: 'Anime all in one place',
      line: 'New seasons, old favourites, all sorted.',
    ),
    GuideStep(
      icon: '🔁',
      title: 'Keep watching',
      line: 'Pick up any episode where you left off.',
    ),
  ];

  // ── Manga ──────────────────────────────────────────────────────────────
  static const manga = [
    GuideStep(
      icon: '📖',
      title: 'Read manga here',
      line: 'Tap a cover, then swipe to turn pages.',
    ),
    GuideStep(
      icon: '🔍',
      title: 'Find a series',
      line: 'Search the title, then start reading.',
    ),
  ];

  // ── Music studio ───────────────────────────────────────────────────────
  static const musicStudio = [
    GuideStep(
      icon: '🎧',
      title: 'Studio sound',
      line: 'Play a song, then tap the badge to pick quality.',
    ),
    GuideStep(
      icon: '🔊',
      title: 'Change the sound yourself',
      line: 'Move the sliders until it feels right.',
    ),
    GuideStep(
      icon: '📻',
      title: 'Keep listening',
      line: 'Queue up songs and drag them into order.',
    ),
  ];

  // ── Equalizer ──────────────────────────────────────────────────────────
  static const eq = [
    GuideStep(
      icon: '🎛️',
      title: 'Shape the sound',
      line: 'Slide each band up or down to taste.',
    ),
    GuideStep(
      icon: '💾',
      title: 'Save what you like',
      line: 'Name your setting and keep it.',
    ),
  ];

  // ── Books reader ───────────────────────────────────────────────────────
  static const books = [
    GuideStep(
      icon: '📚',
      title: 'Read books here',
      line: 'Tap a book, then turn pages one by one.',
    ),
    GuideStep(
      icon: '⚙️',
      title: 'Make reading easy',
      line: 'Set the text size and the page colour.',
    ),
  ];

  // ── Audiobooks ─────────────────────────────────────────────────────────
  static const audiobooks = [
    GuideStep(
      icon: '🎧',
      title: 'Listen instead of read',
      line: 'Play a chapter and keep your hands free.',
    ),
    GuideStep(
      icon: '⏱️',
      title: 'Know where you are',
      line: 'The bar shows how much is left.',
    ),
  ];

  // ── Downloads ──────────────────────────────────────────────────────────
  static const downloads = [
    GuideStep(
      icon: '⬇️',
      title: 'Save to watch offline',
      line: 'Pick quality, tap Save. Easy.',
    ),
    GuideStep(
      icon: '📶',
      title: 'Auto pause on mobile data',
      line: 'Saves data. Resumes on WiFi.',
    ),
    GuideStep(
      icon: '▶️',
      title: 'Watch anytime',
      line: 'Open Downloads, tap Play. No net.',
    ),
  ];

  // ── Offline mode ───────────────────────────────────────────────────────
  static const offline = [
    GuideStep(
      icon: '📴',
      title: 'No internet? No problem',
      line: 'Saved things still play with no bars.',
    ),
    GuideStep(
      icon: '🔄',
      title: 'Back online, it resumes',
      line: 'Waiting things start again by themselves.',
    ),
  ];

  // ── My List ────────────────────────────────────────────────────────────
  static const myList = [
    GuideStep(
      icon: '❤️',
      title: 'Your favourites',
      line: 'Everything you saved, in one list.',
    ),
    GuideStep(
      icon: '👀',
      title: 'Only you see it',
      line: 'Nobody else can open your list.',
    ),
  ];

  // ── Profiles + PIN ─────────────────────────────────────────────────────
  static const profilesPin = [
    GuideStep(
      icon: '👤',
      title: 'Who is watching?',
      line: 'Pick a profile — each one keeps its own list.',
    ),
    GuideStep(
      icon: '🔒',
      title: 'Lock it with a code',
      line: 'Set a 4-digit code to keep it private.',
    ),
  ];

  // ── Debrid (called "fast links" in the UI copy) ────────────────────────
  static const debrid = [
    GuideStep(
      icon: '⚡',
      title: 'Play faster',
      line: 'Add your own account to speed things up.',
    ),
    GuideStep(
      icon: '🔐',
      title: 'Your key stays on your phone',
      line: 'We only use it to fetch your files.',
    ),
  ];

  // ── Live TV ────────────────────────────────────────────────────────────
  static const iptv = [
    GuideStep(
      icon: '📺',
      title: 'Watch live channels',
      line: 'Open the list, tap a channel, it plays.',
    ),
    GuideStep(
      icon: '🔎',
      title: 'Find a channel fast',
      line: 'Type part of the name in the search box.',
    ),
  ];

  // ── Calendar ───────────────────────────────────────────────────────────
  static const calendar = [
    GuideStep(
      icon: '📅',
      title: 'Never miss a day',
      line: 'See when a new episode lands.',
    ),
    GuideStep(
      icon: '🔔',
      title: 'Get a friendly nudge',
      line: 'We ping you when it is ready.',
    ),
  ];

  // ── Stats / Year wrap ──────────────────────────────────────────────────
  static const stats = [
    GuideStep(
      icon: '🏆',
      title: 'Your year in one page',
      line: 'Shows what you watched and loved most.',
    ),
    GuideStep(
      icon: '🔒',
      title: 'Nobody else sees it',
      line: 'This page stays on your phone.',
    ),
  ];

  // ── Subtitles ──────────────────────────────────────────────────────────
  static const subtitles = [
    GuideStep(
      icon: '💬',
      title: 'Words on screen',
      line: 'Pick a style you can read easy.',
    ),
    GuideStep(
      icon: '👀',
      title: 'See preview',
      line: 'Preview shows how it looks.',
    ),
  ];

  // ── Sources health (called "channels" in the UI copy) ──────────────────
  static const sourcesHealth = [
    GuideStep(
      icon: '🟢',
      title: 'Green means good',
      line: 'Green sources play fast.',
    ),
    GuideStep(
      icon: '🔴',
      title: 'Red means resting',
      line: 'Red takes a break. App skips it.',
    ),
    GuideStep(
      icon: '🔄',
      title: 'Tap Retry to wake',
      line: 'Tap Retry, we check again.',
    ),
  ];

  // ── Cloud sync ─────────────────────────────────────────────────────────
  static const cloudSync = [
    GuideStep(
      icon: '☁️',
      title: 'Auto save',
      line: 'Your list saves by itself.',
    ),
    GuideStep(
      icon: '📱',
      title: 'Same everywhere',
      line: 'Phone and laptop stay in sync.',
    ),
  ];

  // ── Watch Together ─────────────────────────────────────────────────────
  static const partyV2 = [
    GuideStep(
      icon: '🏠',
      title: 'Create a room',
      line: 'Name it, share the code. No links needed.',
    ),
    GuideStep(
      icon: '🔢',
      title: 'Friends join',
      line: 'They tap Join, type your code. Done.',
    ),
    GuideStep(
      icon: '▶️',
      title: 'You play, all follow',
      line: 'Press Play — every screen follows you.',
    ),
  ];

  /// Kept for the copy-deck gate and for anyone still linked to it; the card
  /// itself now shows at most 3 steps.
  static const watchParty = [
    GuideStep(
      icon: '👥',
      title: 'Watch Together',
      line: 'Tap Play, friends join with your code.',
    ),
    GuideStep(
      icon: '🔢',
      title: 'Share the code',
      line: 'Send the big code on WhatsApp.',
    ),
    GuideStep(
      icon: '💬',
      title: 'Chat and talk',
      line: 'Chat here. Tap mic to speak.',
    ),
  ];

  // ── Direct messages ────────────────────────────────────────────────────
  static const dms = [
    GuideStep(
      icon: '✉️',
      title: 'Talk to one friend',
      line: 'Open a chat and start typing.',
    ),
    GuideStep(
      icon: '🃏',
      title: 'Send a show or song',
      line: 'Tap the card in chat to play it together.',
    ),
  ];

  // ── Social hub ─────────────────────────────────────────────────────────
  static const socialHub = [
    GuideStep(
      icon: '🫶',
      title: 'See your friends',
      line: 'Everyone you added, in one list.',
    ),
    GuideStep(
      icon: '➕',
      title: 'Add someone',
      line: 'Share your code, they type it in.',
    ),
  ];

  // ── Accent studio ──────────────────────────────────────────────────────
  static const accentStudio = [
    GuideStep(
      icon: '🎨',
      title: 'Pick your colours',
      line: 'Try a colour, the whole app changes.',
    ),
    GuideStep(
      icon: '🧱',
      title: 'Feel the look',
      line: 'Slide for metal, matte or neon.',
    ),
  ];

  // ── Appearance ─────────────────────────────────────────────────────────
  static const appearance = [
    GuideStep(
      icon: '🌓',
      title: 'Light or dark',
      line: 'Switch any time, it saves itself.',
    ),
    GuideStep(
      icon: '🔤',
      title: 'Bigger text',
      line: 'Slide the size until it feels right.',
    ),
  ];

  /// Every guide, keyed by the flag it writes.
  ///
  /// `GuideService.allKeys` is the source of truth for *which* guides exist;
  /// this map is the source of truth for their copy. The P7 test suite fails
  /// if the two ever drift apart.
  static const Map<String, List<GuideStep>> byKey = <String, List<GuideStep>>{
    'home': home,
    'spotlight': spotlight,
    'movie': movie,
    'anime': anime,
    'manga': manga,
    'music_studio': musicStudio,
    'eq': eq,
    'books': books,
    'audiobooks': audiobooks,
    'downloads': downloads,
    'offline': offline,
    'my_list': myList,
    'profiles_pin': profilesPin,
    'debrid': debrid,
    'iptv': iptv,
    'calendar': calendar,
    'stats': stats,
    'subtitles': subtitles,
    'sources_health': sourcesHealth,
    'cloud_sync': cloudSync,
    'party_v2': partyV2,
    'dms': dms,
    'social_hub': socialHub,
    'accent_studio': accentStudio,
    'appearance': appearance,
  };

  /// The copy for [key], or an empty list when the key is unknown.
  static List<GuideStep> forKey(String key) => byKey[key] ?? const <GuideStep>[];
}
