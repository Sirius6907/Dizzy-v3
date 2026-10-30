import 'guide_step.dart';

/// The one optional tour in Dizzy.
///
/// Nothing is ever shown automatically: the tour opens only when the user
/// asks for it from Settings or the profile menu. Three cards, one job each,
/// plain language — long tours get skipped, so there is only one.
class AppGuides {
  AppGuides._();

  static const List<GuideStep> tour = [
    GuideStep(
      icon: '🏠',
      title: 'Everything in one place',
      line: 'Movies, shows, music and books live on the home rows.',
    ),
    GuideStep(
      icon: '🔍',
      title: 'Find it in seconds',
      line: 'Tap search and type a few letters.',
    ),
    GuideStep(
      icon: '👆',
      title: 'Make it yours',
      line: 'Tap the heart to save, then tune the look in Settings.',
    ),
  ];
}
