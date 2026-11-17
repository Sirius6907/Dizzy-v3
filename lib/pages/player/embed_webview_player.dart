import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/stream/stream_model.dart';
import '../../services/adblock/filter_list_service.dart';
import '../../rust/api.dart';

/// Media URL captured from the embed page, ready for mpv.
class CapturedMedia {
  final String url;
  final Map<String, String> headers;

  const CapturedMedia({required this.url, required this.headers});
}

/// Plays an `externalUrl` embed in an in-app, ad-blocked webview and hands the
/// captured media URL to mpv.
///
/// Why a webview at all: several providers stopped exposing a direct media
/// link to plain HTTP clients and answer with a player page instead. The page
/// is the only supported way in, so we load exactly the page the site serves
/// to a browser, block its ad/tracker traffic with the Rust engine, and take
/// the media URL out of the traffic it makes.
///
/// Failure is soft in every direction:
///  * engine unavailable → requests are allowed (playback still works, ads are
///    not blocked);
///  * no media URL captured in [captureTimeout] → the webview keeps playing
///    inside the app (still ad-free), the player is not interrupted;
///  * page load error → [onGiveUp] so the player can fail over.
class EmbedWebviewPlayer extends StatefulWidget {
  final StreamSource source;
  final void Function(CapturedMedia media) onMediaCaptured;
  final VoidCallback? onGiveUp;

  /// How long to wait for a media URL before settling for in-webview playback.
  final Duration captureTimeout;

  const EmbedWebviewPlayer({
    super.key,
    required this.source,
    required this.onMediaCaptured,
    this.onGiveUp,
    this.captureTimeout = const Duration(seconds: 30),
  });

  /// One engine and one list cache per process: the compiled EasyList/uBlock
  /// rules are expensive, and every embed should reuse them.
  static Future<DizzyEngine>? _engineFuture;

  static Future<DizzyEngine> _sharedEngine() async {
    final existing = _engineFuture;
    if (existing != null) return existing;
    final future = _buildEngine();
    _engineFuture = future;
    try {
      return await future;
    } catch (_) {
      // Do not cache a failure: the next open retries.
      _engineFuture = null;
      rethrow;
    }
  }

  static Future<DizzyEngine> _buildEngine() async {
    final rules = await FilterListService.loadRules();
    return newEngine(rules: rules);
  }

  /// The blocking decision. Always allows the page document itself — an ad
  /// blocker must never be the reason the player cannot open.
  static Future<bool> shouldBlock(
    DizzyEngine engine,
    String url,
    String pageHost,
    String resourceType,
  ) async {
    if (resourceType == 'document' && _hostOf(url) == pageHost) return false;
    return engineMatch(
      engine: engine,
      url: url,
      sourceHost: pageHost,
      resourceType: resourceType,
    );
  }

  /// Webview vocabulary for a URL. Interception only gives a URL and whether
  /// it is the main frame, so this maps by shape.
  static String resourceTypeFor(String url, {bool? isForMainFrame}) {
    if (isForMainFrame == true) return 'document';
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.js')) return 'script';
    if (path.endsWith('.css')) return 'stylesheet';
    if (path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.svg')) {
      return 'image';
    }
    if (path.endsWith('.woff') ||
        path.endsWith('.woff2') ||
        path.endsWith('.ttf')) {
      return 'font';
    }
    if (isMediaUrl(url)) return 'media';
    return 'xhr';
  }

  /// True for a URL mpv can open. Segment requests are explicitly excluded:
  /// they are part of a stream whose playlist was (or will be) captured.
  static bool isMediaUrl(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (path.endsWith('.ts') ||
        path.endsWith('.m4s') ||
        path.endsWith('.aac') ||
        path.endsWith('.vtt')) {
      return false;
    }
    return path.endsWith('.m3u8') ||
        path.endsWith('.mpd') ||
        path.endsWith('.mp4') ||
        path.endsWith('.m4v') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.contains('/hls/');
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  @override
  State<EmbedWebviewPlayer> createState() => _EmbedWebviewPlayerState();
}

class _EmbedWebviewPlayerState extends State<EmbedWebviewPlayer> {
  InAppWebViewController? _controller;
  DizzyEngine? _engine;
  bool _booting = true;
  bool _captured = false;
  bool _failed = false;
  Timer? _captureTimer;
  int _blocked = 0;
  String _pageHost = '';

  @override
  void initState() {
    super.initState();
    final embed = widget.source.externalUrl ?? '';
    _pageHost = EmbedWebviewPlayer._hostOf(embed);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      _engine = await EmbedWebviewPlayer._sharedEngine();
    } catch (e) {
      // Ads are not blocked, but the page still plays. Never a crash, never a
      // dead end.
      debugPrint('[Embed] adblock engine unavailable (soft): $e');
      _engine = null;
    }
    if (!mounted) return;
    setState(() => _booting = false);
    _captureTimer = Timer(widget.captureTimeout, () {
      if (_captured || !mounted) return;
      debugPrint('[Embed] no media URL captured — keeping in-webview playback');
    });
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    if (_blocked > 0) {
      debugPrint('[Embed] session blocked $_blocked ad/tracker requests');
    }
    super.dispose();
  }

  Future<WebResourceResponse?> _intercept(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final url = request.url.toString();
    final engine = _engine;
    if (engine == null) return null;

    final type = EmbedWebviewPlayer.resourceTypeFor(
      url,
      isForMainFrame: request.isForMainFrame,
    );

    if (type == 'media' && !_captured) {
      if (!EmbedWebviewPlayer.isMediaUrl(url)) return null;
      if (EmbedWebviewPlayer._hostOf(url) == _pageHost) return null;
      _captured = true;
      _captureTimer?.cancel();
      final scheme = Uri.tryParse(widget.source.externalUrl ?? '')?.scheme;
      final referer = '${scheme ?? 'https'}://$_pageHost/';
      debugPrint('[Embed] media captured from ${EmbedWebviewPlayer._hostOf(url)}');
      // Let the request through as well: if the handoff is refused, the
      // webview has already started playing instead of going black.
      widget.onMediaCaptured(
        CapturedMedia(
          url: url,
          headers: {
            'Referer': referer,
            'User-Agent': PlayerSettingsUserAgent.value,
          },
        ),
      );
      return null;
    }

    final block = await EmbedWebviewPlayer.shouldBlock(
      engine,
      url,
      _pageHost,
      type,
    );
    if (!block) return null;

    _blocked++;
    if (_blocked <= 10) {
      debugPrint('[Embed] block ${EmbedWebviewPlayer._hostOf(url)} ($type)');
    }
    return WebResourceResponse(
      data: Uint8List(0),
      contentType: 'text/plain',
      statusCode: 200,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _EmbedMessage(
        title: 'This source did not open',
        actionLabel: 'Try again',
        onAction: () {
          setState(() => _failed = false);
          _controller?.reload();
        },
      );
    }
    if (_booting) {
      return const _EmbedMessage(title: 'Opening player…');
    }

    final embed = widget.source.externalUrl ?? '';
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(embed)),
          initialSettings: InAppWebViewSettings(
            useShouldInterceptRequest: true,
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            supportZoom: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            disableContextMenu: true,
            isInspectable: kDebugMode,
            transparentBackground: false,
          ),
          onWebViewCreated: (controller) => _controller = controller,
          shouldInterceptRequest: _intercept,
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame != true) return;
            debugPrint('[Embed] page error: ${error.description}');
            if (mounted) setState(() => _failed = true);
            widget.onGiveUp?.call();
          },
        ),
        if (_captured)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _EmbedBar(text: 'Starting video…'),
          ),
      ],
    );
  }
}

/// The app's own UA, shared with the player so the CDN sees one client.
class PlayerSettingsUserAgent {
  PlayerSettingsUserAgent._();
  static const value =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
}

class _EmbedBar extends StatelessWidget {
  final String text;
  const _EmbedBar({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbedMessage extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmbedMessage({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAction == null)
              const CircularProgressIndicator(strokeWidth: 2)
            else
              const Icon(Icons.error_outline, color: Colors.white70, size: 32),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
