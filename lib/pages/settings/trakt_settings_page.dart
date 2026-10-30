import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/metadata/watched_history_import_service.dart';

class TraktSettingsPage extends StatefulWidget {
  const TraktSettingsPage({super.key});

  @override
  State<TraktSettingsPage> createState() => _TraktSettingsPageState();
}

class _TraktSettingsPageState extends State<TraktSettingsPage> {
  bool _isAuthed = false;
  bool _isLoading = true;
  String? _username;

  // Device Code Pairing
  bool _pairing = false;
  String? _userCode;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final authed = await TraktService.instance.isAuthenticated();
    String? user;
    if (authed) {
      user = await TraktService.instance.getUsername();
    }
    if (mounted) {
      setState(() {
        _isAuthed = authed;
        _username = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _startPairing() async {
    setState(() {
      _pairing = true;
      _userCode = null;
    });

    final res = await TraktService.instance.requestDeviceCode();
    if (!mounted) return;
    if (res == null) {
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request Trakt pairing code.')),
      );
      return;
    }

    final userCode = res['user_code'] as String? ?? '';
    final deviceCode = res['device_code'] as String? ?? '';
    final verifyUrl =
        res['verification_url'] as String? ?? 'https://trakt.tv/activate';
    final interval = (res['interval'] as int? ?? 5).clamp(2, 30);

    setState(() {
      _userCode = userCode;
    });

    // Auto-launch URL
    _openBrowser(verifyUrl);

    // Start Polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: interval), (t) async {
      final status = await TraktService.instance.pollDeviceToken(deviceCode);
      if (status == null) {
        // Success!
        t.cancel();
        if (mounted) {
          setState(() {
            _pairing = false;
            _isAuthed = true;
          });
          _checkStatus();
          MyListService.syncAll();
          ContinueWatchingService.syncCloudSessions();
        }
      } else if (status == 'expired_token' || status == 'access_denied') {
        t.cancel();
        if (mounted) {
          setState(() => _pairing = false);
        }
      }
    });
  }

  Future<void> _openBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        debugPrint('[Trakt] Browser launch error: $e');
      }
    }
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await TraktService.instance.logout();
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight
        ? PrismLight.inkSoft
        : Colors.white.withValues(alpha: 0.55);
    final inkFaint = isLight ? PrismLight.inkFaint : Colors.white38;
    final cardColor = isLight ? PrismLight.raisedTop : PrismDark.raised;
    final borderColor = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: palette.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: palette.appBarBackgroundColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Trakt.tv Synchronization',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Connect your Trakt.tv account to seamlessly synchronize your watch history, watchlist, continue watching progress, and ratings across all your devices.',
                  style: TextStyle(fontSize: 13.5, color: inkSoft, height: 1.4),
                ),
              ),

              // Status Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAuthed
                        ? const Color(0xFFED1C24).withValues(alpha: 0.35)
                        : borderColor,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 460;

                    final infoWidget = Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFED1C24,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.movie_filter_rounded,
                            color: Color(0xFFED1C24),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Trakt.tv',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: ink,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (_isAuthed
                                                  ? const Color(0xFF10B981)
                                                  : inkFaint)
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _isAuthed ? 'CONNECTED' : 'DISCONNECTED',
                                      style: TextStyle(
                                        fontSize: PrismType.micro,
                                        fontWeight: FontWeight.w800,
                                        color: _isAuthed
                                            ? (isLight
                                                  ? inkSoft
                                                  : const Color(0xFF10B981))
                                            : inkSoft,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isLoading
                                    ? 'Checking credentials...'
                                    : _isAuthed
                                    ? 'Logged in as ${_username ?? 'Trakt User'}'
                                    : 'Sign in to activate two-way cloud sync',
                                style: TextStyle(fontSize: 13, color: inkSoft),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    Widget? actionWidget;
                    if (_isAuthed) {
                      actionWidget = OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PrismAccent.text(isLight),
                          side: BorderSide(
                            color: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onPressed: _logout,
                        child: const Text(
                          'Disconnect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    } else if (!_pairing) {
                      actionWidget = ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFED1C24),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: _startPairing,
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text(
                          'Pair Account',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          infoWidget,
                          if (actionWidget != null) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: actionWidget,
                            ),
                          ],
                        ] else ...[
                          Row(
                            children: [
                              Expanded(child: infoWidget),
                              if (actionWidget != null) ...[
                                const SizedBox(width: 14),
                                actionWidget,
                              ],
                            ],
                          ),
                        ],
                        if (_pairing && _userCode != null) ...[
                          const SizedBox(height: 20),
                          Divider(color: borderColor),
                          const SizedBox(height: 16),
                          Center(
                            child: Column(
                              children: [
                                Text(
                                  'Enter this activation code at trakt.tv/activate:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: inkSoft,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _userCode!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Code copied to clipboard!',
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLight
                                          ? PrismLight.raisedBottom
                                          : Colors.black45,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFED1C24,
                                        ).withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _userCode!,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 4,
                                            color: ink,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.copy_rounded,
                                          color: inkSoft,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isLight
                                        ? PrismLight.raisedBottom
                                        : Colors.white.withValues(alpha: 0.12),
                                    foregroundColor: ink,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _openBrowser('https://trakt.tv/activate'),
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Open trakt.tv/activate',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFED1C24),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Waiting for permission on trakt.tv...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Cloud Sync Actions
              if (_isAuthed) ...[
                Text(
                  'Cloud Sync Controls',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: inkSoft,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  tileColor: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: borderColor),
                  ),
                  leading: const Icon(
                    Icons.sync_rounded,
                    color: Color(0xFF7C5CFF),
                  ),
                  title: Text(
                    'Sync Watchlist & Continue Watching Now',
                    style: TextStyle(color: ink, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Manually triggers an immediate pull from Trakt',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: inkFaint,
                  ),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with Trakt.tv...')),
                    );
                    await Future.wait([
                      MyListService.syncAll(),
                      ContinueWatchingService.syncCloudSessions(),
                      WatchedHistoryImportService.importTraktWatched(),
                    ]);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Trakt sync & watched import complete!',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
