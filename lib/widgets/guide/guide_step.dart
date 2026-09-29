/// One page of an intro card: a big emoji, a short title, and a single
/// Easy English line saying what the feature does.
///
/// Deliberately tiny — a guide is a nudge, not a manual.
class GuideStep {
  final String icon;
  final String title;
  final String line;

  const GuideStep({required this.icon, required this.title, required this.line});
}
