import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/dizzy_tactile.dart';
import '../../design/dizzy_tokens.dart';
import '../../services/profiles/device_merge_policy.dart';
import '../../services/profiles/restore_service.dart';
import '../../widgets/common/offline_aware_scaffold.dart';
import '../../widgets/tactile/dizzy_tactile_button.dart';

/// F3 — "Naya phone? Sab wapas." Three steps, Easy English, no jargon.
///
/// The rule this screen lives by: a waiting screen is never blank. Every
/// stage shows a line saying what is happening in plain words, and every
/// stage can be left with one tap. If something goes wrong the person sees
/// a sentence they can act on — never an error code.
class RestorePage extends StatefulWidget {
  const RestorePage({super.key});

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    RestoreService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    RestoreService.instance.removeListener(_onChange);
    _codeController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String get _line {
    final msg = RestoreService.instance.message;
    if (msg == null || msg.isEmpty) return 'Type the code from your old phone.';
    return msg;
  }

  bool get _busy =>
      RestoreService.instance.stage == RestoreStage.checking ||
      RestoreService.instance.stage == RestoreStage.merging;

  Future<void> _getCode() async {
    await RestoreService.instance.requestCode();
  }

  Future<void> _redeem() async {
    FocusScope.of(context).unfocus();
    await RestoreService.instance.redeem(_codeController.text);
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final stage = RestoreService.instance.stage;
    final result = RestoreService.instance.result;

    return OfflineAwareScaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Bring things back', style: TextStyle(color: DizzyVoid.bone)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DizzySpace.lg),
        children: [
          _stepOne(),
          const SizedBox(height: DizzySpace.lg),
          _stepTwo(),
          const SizedBox(height: DizzySpace.lg),
          _statusLine(stage),
          if (result != null) ...[
            const SizedBox(height: DizzySpace.md),
            _resultCard(result),
          ],
          const SizedBox(height: DizzySpace.md),
          _leaveButton(),
        ],
      ),
    );
  }

  Widget _stepOne() {
    return _panel(
      icon: Icons.phone_android,
      title: '1. On your old phone',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Open Dizzy and tap "Bring things back". Read out the short code it shows.',
            style: TextStyle(color: DizzyVoid.ash, height: 1.4),
          ),
          const SizedBox(height: DizzySpace.md),
          FutureBuilder<String?>(
            future: RestoreService.instance.myCode(),
            builder: (context, snap) {
              final code = snap.data;
              if (code == null || code.isEmpty) {
                return const Text(
                  'No code on this phone yet? Get one below.',
                  style: TextStyle(color: DizzyVoid.ash, fontSize: 12),
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        color: DizzyGlow.volt,
                        fontSize: 28,
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () => _copyCode(code),
                    icon: const Icon(Icons.copy, color: DizzyVoid.ash),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: DizzySpace.sm),
          DizzyTactileButton(
            height: 44,
            gradient: DizzyGradients.emberButton,
            glowColor: DizzyGlow.volt,
            onTap: _busy ? null : _getCode,
            child: Text(
              _busy ? 'Working...' : 'Get a code for this phone',
              style: const TextStyle(color: DizzyVoid.bone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTwo() {
    return _panel(
      icon: Icons.keyboard,
      title: '2. On this phone',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type the code you read out. We keep your lists, your history and where you stopped.',
            style: TextStyle(color: DizzyVoid.ash, height: 1.4),
          ),
          const SizedBox(height: DizzySpace.md),
          TextField(
            controller: _codeController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.text,
            maxLength: 8,
            style: const TextStyle(
              color: DizzyVoid.bone,
              fontSize: 24,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'CODE',
              hintStyle: const TextStyle(color: DizzyVoid.ash, letterSpacing: 6),
              filled: true,
              fillColor: DizzyVoid.voidA,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: DizzyEdge.hairline,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: DizzyEdge.hairline,
              ),
            ),
            onSubmitted: (_) => _redeem(),
          ),
          const SizedBox(height: DizzySpace.sm),
          DizzyTactileButton(
            height: 48,
            gradient: DizzyGradients.emberButton,
            glowColor: DizzyGlow.volt,
            onTap: _busy ? null : _redeem,
            child: Text(
              _busy ? 'Bringing back...' : 'Bring everything back',
              style: const TextStyle(color: DizzyVoid.bone, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(RestoreStage stage) {
    final (IconData icon, Color color) = switch (stage) {
      RestoreStage.checking => (Icons.hourglass_top, DizzyVoid.ash),
      RestoreStage.merging => (Icons.sync, DizzyGlow.volt),
      RestoreStage.done => (Icons.check_circle, DizzyGlow.volt),
      RestoreStage.failed => (Icons.info_outline, DizzyGlow.red),
      RestoreStage.idle => (Icons.info_outline, DizzyVoid.ash),
    };
    return Row(
      children: [
        if (_busy) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: DizzySpace.sm),
        ] else ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: DizzySpace.sm),
        ],
        Expanded(
          child: Text(
            _line,
            style: const TextStyle(color: DizzyVoid.bone, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(DeviceMergeResult result) {
    final rows = <(String, int)>[
      ('Titles', result.watchlistAdded),
      ('Things you watched', result.historyAdded),
      ('Friends', result.friendsAdded),
      ('Where you stopped', result.progressAdded),
    ].where((r) => r.$2 > 0).toList();

    if (rows.isEmpty) {
      return const Text(
        'Nothing new came back. That is fine — you can try the code again later.',
        style: TextStyle(color: DizzyVoid.ash),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(r.$1, style: const TextStyle(color: DizzyVoid.ash)),
                ),
                Text(
                  '${r.$2}',
                  style: const TextStyle(
                    color: DizzyVoid.bone,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _leaveButton() {
    return TextButton(
      onPressed: _busy
          ? null
          : () {
              RestoreService.instance.reset();
              Navigator.of(context).maybePop();
            },
      child: const Text('Close', style: TextStyle(color: DizzyVoid.ash)),
    );
  }

  Widget _panel({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: DizzyGlow.volt),
            const SizedBox(width: DizzySpace.sm),
            Text(
              title,
              style: const TextStyle(
                color: DizzyVoid.bone,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: DizzySpace.sm),
        child,
      ],
    );
  }
}
