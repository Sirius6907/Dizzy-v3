import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/movie/movie.dart';
import '../../../utils/navigation/route_transitions.dart';
import '../../details/details_page.dart';
import 'watch_addon_icon.dart';
import 'watch_copy_magnet_button.dart';

import '../../../models/movie/movie_detail.dart';
import '../../../models/movie/video.dart';
import '../../../models/stream/stream_model.dart';
import '../player_screen.dart';
import 'watch_style.dart';

class WatchSourceCard extends StatefulWidget {
  final StreamSource source;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail detail;
  final Video? episode;
  final Duration? initialPosition;
  final VoidCallback? onUserPicked;
  /// Verified backups for silent failover (from the probe race list).
  final List<StreamSource>? failoverCandidates;

  const WatchSourceCard({super.key,
    required this.source,
    this.backdropUrl,
    this.logoUrl,
    required this.detail,
    this.episode,
    this.initialPosition,
    this.onUserPicked,
    this.failoverCandidates,
  });

  @override
  State<WatchSourceCard> createState() => WatchSourceCardState();
}

class WatchSourceCardState extends State<WatchSourceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final badges = <Widget>[];

    // Quality badge
    if (s.quality != null) {
      Color badgeColor;
      switch (s.quality) {
        case '4K':
          badgeColor = const Color(0xFFFF6B6B);
          break;
        case '1080p':
          badgeColor = const Color(0xFF51CF66);
          break;
        case '720p':
          badgeColor = const Color(0xFF339AF0);
          break;
        default:
          badgeColor = WatchColors.textTertiary;
      }
      badges.add(_badge(s.quality!, badgeColor));
    }

    if (s.isHDR) badges.add(_badge('HDR', const Color(0xFFFFD43B)));
    if (s.codec != null) badges.add(_badge(s.codec!, WatchColors.textTertiary));
    if (s.fileSize != null) badges.add(_badge(s.fileSize!, WatchColors.textTertiary));
    if (s.seeders != null) {
      final seederColor = s.seeders! >= 20
          ? const Color(0xFF10B981)
          : (s.seeders! >= 5 ? const Color(0xFFFFD43B) : const Color(0xFFFF922B));
      badges.add(_badge('👤 ${s.seeders} Seeds', seederColor));
    }

    // Audio Language / Dub badge
    final audioBadge = s.getAudioBadge(mediaTitle: widget.detail.name);
    if (audioBadge != null) {
      Color audioBadgeColor;
      if (audioBadge.contains('MULTI')) {
        audioBadgeColor = const Color(0xFFB197FC);
      } else if (audioBadge.contains('HINDI') ||
          audioBadge.contains('TELUGU') ||
          audioBadge.contains('TAMIL') ||
          audioBadge.contains('MALAYALAM') ||
          audioBadge.contains('KANNADA') ||
          audioBadge.contains('PUNJABI')) {
        audioBadgeColor = const Color(0xFFFF922B);
      } else if (audioBadge.contains('GER')) {
        audioBadgeColor = const Color(0xFFFFD43B);
      } else if (audioBadge.contains('FRE')) {
        audioBadgeColor = const Color(0xFF4DABF7);
      } else if (audioBadge.contains('SPA')) {
        audioBadgeColor = const Color(0xFFFAB005);
      } else if (audioBadge.contains('RUS')) {
        audioBadgeColor = const Color(0xFF22B8CF);
      } else if (audioBadge.contains('JPN')) {
        audioBadgeColor = const Color(0xFFFF8787);
      } else if (audioBadge.contains('ITA')) {
        audioBadgeColor = const Color(0xFF69DB7C);
      } else {
        audioBadgeColor = WatchColors.textTertiary;
      }
      badges.add(_badge(audioBadge, audioBadgeColor));
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onUserPicked?.call(); // mark user choice — stop autoplay race

              if (s.externalUrl != null && s.externalUrl!.isNotEmpty) {
                if (s.externalUrl!.startsWith('stremio://')) {
                  // Example: stremio:///detail/movie/tt28479262
                  final uriStr = s.externalUrl!.replaceFirst(
                    'stremio:///',
                    'stremio://',
                  );
                  final uri = Uri.parse(uriStr);
                  final segments = uri.pathSegments;
                  if (uri.host == 'detail' && segments.length >= 2) {
                    final type = segments[0];
                    final id = segments[1];
                    final movie = Movie(
                      id: id,
                      type: type,
                      name: s.name ?? 'Unknown',
                      addonBaseUrl: 'https://v3-cinemeta.strem.io',
                    );
                    Navigator.push(
                      context,
                      CinematicSlideRoute(page: DetailsPage(movie: movie)),
                    );
                    return;
                  }
                  return;
                } else {
                  // Fallback for http URLs or other schemes
                  launchUrl(
                    Uri.parse(s.externalUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                  return;
                }
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    source: s,
                    title: s.displayTitle,
                    backdropUrl: widget.backdropUrl,
                    logoUrl: widget.logoUrl,
                    detail: widget.detail,
                    episode: widget.episode,
                    initialPosition: widget.initialPosition,
                    failoverSources: widget.failoverCandidates,
                  ),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _hovered
                    ? WatchColors.surfaceLight.withValues(alpha: 0.9)
                    : WatchColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered
                      ? WatchColors.accent.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: WatchColors.accent.withValues(alpha: 0.08),
                          blurRadius: 16,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // Addon icon
                  WatchAddonIcon(addonName: s.addonName),
                  const SizedBox(width: WatchSpace.sm),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name != null && s.name!.isNotEmpty
                              ? s.name!
                              : s.addonName,
                          style: const TextStyle(
                            color: WatchColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (s.title != null && s.title!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            s.title!,
                            style: const TextStyle(
                              color: WatchColors.textTertiary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (s.description != null &&
                            s.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            s.description!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: WatchColors.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 4, runSpacing: 4, children: badges),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: WatchSpace.xs),
                  if (s.isMagnet && s.magnetUrl != null) ...[
                    WatchCopyMagnetButton(magnetUrl: s.magnetUrl!),
                    const SizedBox(width: 8),
                  ],
                  // Play chevron
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? WatchColors.accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: _hovered ? WatchColors.accent : WatchColors.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

