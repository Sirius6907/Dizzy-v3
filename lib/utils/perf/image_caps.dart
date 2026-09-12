/// Polish P14 — decode caps in ONE place (≤3GB RAM safe).
///
/// Frozen contract (P23): backdrop ≤960px, logo ≤400px.
/// Every CachedNetworkImage takes its cap from here — no ad-hoc numbers.
/// RAM math: 960×540×4B ≈ 2MB per backdrop (vs 8MB at 1920).
abstract final class ImageCaps {
  const ImageCaps._();

  /// Full-bleed backdrops / hero art.
  static const int kBackdrop = 960;

  /// Grid cards (2:3 posters).
  static const int kCardW = 500;
  static const int kCardH = 750;

  /// Small thumbs / row posters.
  static const int kThumb = 220;

  /// Overlay logos.
  static const int kLogo = 400;

  /// Clamp any requested decode width into the safe range.
  static int capWidth(int requested) =>
      requested.clamp(kThumb, kBackdrop);
}
