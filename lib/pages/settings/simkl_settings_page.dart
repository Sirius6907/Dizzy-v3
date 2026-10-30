import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dizzy/design/prism_tokens.dart';
import '../../services/simkl/simkl_service.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/continue_watching/continue_watching_service.dart';
import '../../services/metadata/watched_history_import_service.dart';

class SimklSettingsPage extends StatefulWidget {
  const SimklSettingsPage({super.key});

  @override
  State<SimklSettingsPage> createState() => _SimklSettingsPageState();
}

class _SimklSettingsPageState extends State<SimklSettingsPage> {
  bool _isAuthed = false;
  bool _isLoading = true;
  String? _username;

  // PIN Flow Pairing
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
    final authed = await SimklService.instance.isAuthenticated();
    String? user;
    if (authed) {
      user = await SimklService.instance.getUsername();
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

    final res = await SimklService.instance.requestPin();
    if (!mounted) return;
    if (res == null) {
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request Simkl PIN code.')),
      );
      return;
    }

    final userCode = res['user_code'] as String? ?? '';
    final verifyUrl =
        res['verification_url'] as String? ?? 'https://simkl.com/pin';
    final interval = (res['interval'] as int? ?? 5).clamp(2, 30);

    setState(() {
      _userCode = userCode;
    });

    // Auto-launch URL
    _openBrowser(verifyUrl);

    // Start Polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: interval), (t) async {
      final status = await SimklService.instance.pollPin(userCode);
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
        debugPrint('[Simkl] Browser launch error: $e');
      }
    }
  }

  Future<void> _logout() async {
    _pollTimer?.cancel();
    await SimklService.instance.logout();
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
          'Simkl Synchronization',
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
                  'Connect your Simkl account to synchronize Movies, TV Shows, and Anime watchlists, continue watching progress, and custom lists.',
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
                        ? const Color(0xFF00ADFF).withValues(alpha: 0.35)
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
                              0xFF00ADFF,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tv_rounded,
                            color: Color(0xFF00ADFF),
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
                                    'Simkl',
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
                                    ? 'Logged in as ${_username ?? 'Simkl User'}'
                                    : 'Sign in with PIN to activate Simkl cloud sync',
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
                          backgroundColor: const Color(0xFF00ADFF),
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
                        icon: const Icon(Icons.pin_rounded, size: 18),
                        label: const Text(
                          'Connect Simkl',
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
                                  'Enter this PIN code at simkl.com/pin:',
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
                                          'PIN copied to clipboard!',
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
                                          0xFF00ADFF,
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
                                      _openBrowser('https://simkl.com/pin'),
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Open simkl.com/pin',
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
                                        color: Color(0xFF00ADFF),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Waiting for PIN approval on simkl.com...',
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
                    color: Color(0xFF00ADFF),
                  ),
                  title: Text(
                    'Sync Simkl Watchlist & Continue Watching',
                    style: TextStyle(color: ink, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Manually triggers an immediate pull from Simkl',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: inkFaint,
                  ),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with Simkl...')),
                    );
                    await Future.wait([
                      MyListService.syncAll(),
                      ContinueWatchingService.syncCloudSessions(),
                      WatchedHistoryImportService.importSimklWatched(),
                    ]);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Simkl sync & watched import complete!',
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
