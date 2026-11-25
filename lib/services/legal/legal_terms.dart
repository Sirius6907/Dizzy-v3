/// The legal text Dizzy shows, and the version it is published under.
///
/// One constant decides when someone has to agree again: bump [version] (and
/// the sub-versions if only one document changed) whenever the wording below
/// changes in a way a person should see. [LegalAcceptanceService] compares the
/// stored version against this one, so the onboarding gate re-opens by itself
/// and no other code needs to know about it.
///
/// Everything in here has to stay true to the code: if a new upload is added,
/// it gets a section here in the same change. Promising less than we do is a
/// bug; promising more is a lie.
library;

class LegalSection {
  const LegalSection(this.headline, this.body);

  final String headline;
  final String body;
}

class LegalTerms {
  const LegalTerms._();

  /// Bump to re-prompt everyone. Format: YYYY-MM-DD of publication.
  ///
  /// 2026-11-26 — one-tap consent. The gate stopped being four opt-in
  /// switches and became a single "Accept" that turns all five on, so every
  /// install has to see (and agree to) that new deal. This also carries the
  /// first honest wording about titles: `user_events` has always stored the
  /// name of what you play, add, rate and search for, and the old text said
  /// the opposite.
  static const String version = '2026-11-26';
  static const String termsVersion = version;
  static const String privacyVersion = version;

  static const String title = 'Terms & Privacy';

  /// Raw error telemetry is rolled into daily counts and the raw rows dropped.
  /// Keep in step with `device_logs_purge` (cron runs it with 90 days).
  static const int rawTelemetryDays = 90;

  /// Device codes that stop being used are pruned after this long.
  static const int deviceCodeDays = 180;

  static const List<LegalSection> sections = [
    LegalSection(
      'Using Dizzy',
      'Dizzy is a player. It does not host, sell or stream anything itself — '
          'it plays media from sources you add, and links you already have. '
          'You are responsible for having the right to watch what you play.',
    ),
    LegalSection(
      'No account needed',
      'The app works fully offline with no sign-up. A cloud identity is '
          'created silently the first time you open the app so that sync, '
          'watch parties and your username can work; it holds no email, phone '
          'number or real name unless you add one yourself.',
    ),
    LegalSection(
      'What never leaves your device',
      'Your files and folders, your messages, your contacts, your location, '
          'any advertising identifier, and anything you do inside the 18+ '
          'section. Dizzy does not read them and has nowhere to send them.',
    ),
    LegalSection(
      'What can leave your device — only if you switch it on',
      'App experience data: install, app version and platform. Taste '
          'preferences: the titles you play, add to your list, rate and search '
          'for, with their genre, language and a timestamp, plus the rolled-up '
          'genre scores built from them (such as action:0.8). The title is what '
          'makes a recommendation possible; nothing from the 18+ section is '
          'included. Crash counts: the kind of problem and the screen it '
          'happened on, never a link or file name. Live activity: what kind of '
          'thing you are playing (watch, listen, read) so admins can see who is '
          'online. Watch Party: microphone audio through LiveKit and room '
          'membership, only while you are in a room. Every one of these has '
          'its own switch in Settings → Privacy, and switching one off stops '
          'that upload.',
    ),
    LegalSection(
      'Your device code',
      'This install is known to the server as a 7-digit code, shown as '
          'DIZ-1234567. It is what links an install to your username and to the '
          'error reports you send, so support can find your device without ever '
          'seeing a hardware ID. The hardware ID itself is stored only as a '
          'one-way salted hash, is never shown to anyone, and cannot be turned '
          'back into your device. You can see and copy your code in Settings → '
          'About.',
    ),
    LegalSection(
      'How long we keep things',
      'Raw error reports are kept for $rawTelemetryDays days, then replaced by '
          'daily counts with no individual rows. Device codes that stop being '
          'used are removed after $deviceCodeDays days. Your acceptance of this '
          'text is kept for as long as the account exists, because it is the '
          'record that you agreed.',
    ),
    LegalSection(
      'Your controls',
      'Every optional upload has a switch in Settings → Privacy. "Delete my '
          'cloud data" removes your consent records, taste scores, backups, '
          'profiles, rooms, chat and the record of this agreement from the '
          'server; the app keeps working locally afterwards. The install itself '
          'stays registered under its device code so the app can still sync — '
          'ask an admin to revoke the device to cut that link too.',
    ),
    LegalSection(
      'Children',
      'Dizzy is not directed at children. The 18+ section is locked behind a '
          'birth-year check on the device plus an explicit allow from an admin, '
          'and kids profiles can never open it.',
    ),
    LegalSection(
      'Changes to this text',
      'When this text changes, its version changes with it and the app asks '
          'you to agree again the next time you open it. The version you agreed '
          'to, and the date, are shown in Settings → Privacy.',
    ),
  ];
}
