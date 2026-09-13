class MusicCardSizing {
  final double cardWidth;
  final double totalHeight;

  const MusicCardSizing(this.cardWidth, this.totalHeight);

  factory MusicCardSizing.fromWidth(double width) {
    if (width >= 1200) return const MusicCardSizing(170, 240);
    if (width >= 800) return const MusicCardSizing(150, 215);
    if (width >= 450) return const MusicCardSizing(140, 200);
    return const MusicCardSizing(125, 185);
  }
}
