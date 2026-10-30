import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/prism_tokens.dart';
import '../../pages/my_list/restore_page.dart';
import '../../services/social/dizzy_social_service.dart';
import '../../services/social/username_gate_state.dart';
import '../../services/theme/app_theme_service.dart';
import '../prism/prism_button.dart';

enum UsernameGateMode { claim, welcomeBack }

/// v1.3.3 first-run username gate. Full screen, non-dismissible: the name
/// is the account's social identity, and asking once beats asking forever.
/// The only exits are a claimed name, an adopted previous account, or the
/// deliberate "Later" after two real failures (a media app must never be
/// bricked by a name prompt on a bad network).
class UsernameGateScreen extends StatefulWidget {
  const UsernameGateScreen({
    super.key,
    this.mode = UsernameGateMode.claim,
    this.previous,
  });

  final UsernameGateMode mode;
  final ReturningUser? previous;

  @override
  State<UsernameGateScreen> createState() => _UsernameGateScreenState();
}

enum _Status { idle, checking, ok, taken, reserved, bad, rateLimited, offline }

class _UsernameGateScreenState extends State<UsernameGateScreen> {
  late UsernameGateMode _mode = widget.mode;
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  _Status _status = _Status.idle;
  bool _busy = false;
  bool _done = false;
  int _failures = 0;
  String? _serverLine;

  bool get _isLight => AppThemeService.currentPalette.value.isLight;
  Color get _ink => _isLight ? PrismLight.ink : PrismDark.ink;
  Color get _inkSoft => _isLight ? PrismLight.inkSoft : PrismDark.inkSoft;
  Color get _inkFaint => _isLight ? PrismLight.inkFaint : PrismDark.inkFaint;
  Color get _well => _isLight ? PrismLight.raisedTop : PrismDark.raisedTop;
  Color get _accent => AppThemeService.currentPalette.value.primaryColor;
  Color get _accentText => PrismAccent.text(_isLight);

  @override
  void initState() {
    super.initState();
    if (_mode != UsernameGateMode.claim) return;
    // Old builds cached a name locally that the server never stored (the
    // usernames table shipped after those profiles). Prefill it so the
    // person confirms the name their profile already shows instead of
    // retyping it — the availability check still has the final word.
    final cached = DizzySocialService.currentUsername.value?.trim() ?? '';
    if (UsernameGatePolicy.localProblem(cached) != null) return;
    _name.text = UsernameGatePolicy.normalize(cached);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onChanged(_name.text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? get _hint {
    switch (_status) {
      case _Status.idle:
        return null;
      case _Status.checking:
        return 'Checking…';
      case _Status.ok:
        return 'Looks good.';
      case _Status.taken:
        return 'That name is taken. Try another.';
      case _Status.reserved:
        return 'That name is reserved.';
      case _Status.bad:
        return _problemLine(UsernameGatePolicy.localProblem(_name.text));
      case _Status.rateLimited:
        return 'Too many tries. Wait a minute.';
      case _Status.offline:
        return "Can't check right now — tap Continue and we'll try.";
    }
  }

  static String _problemLine(UsernameProblem? p) {
    switch (p) {
      case UsernameProblem.empty:
      case UsernameProblem.tooShort:
        return 'At least 3 characters.';
      case UsernameProblem.tooLong:
        return '20 characters max.';
      case UsernameProblem.badChars:
        return 'Letters, numbers and _ only.';
      case null:
        return '';
    }
  }

  Color get _hintColor {
    if (_status == _Status.ok) return _accentText;
    if (_status == _Status.idle ||
        _status == _Status.checking ||
        _status == _Status.offline) {
      return _inkFaint;
    }
    return PrismAccent.danger;
  }

  void _onChanged(String raw) {
    setState(() => _serverLine = null);
    _debounce?.cancel();
    final problem = UsernameGatePolicy.localProblem(raw);
    if (problem != null) {
      setState(() => _status = _Status.bad);
      return;
    }
    setState(() => _status = _Status.checking);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final available = await UsernameGateState.isAvailable(raw);
      if (!mounted) return;
      if (available == null) {
        setState(() => _status = _Status.offline);
      } else if (available) {
        setState(() => _status = _Status.ok);
      } else {
        setState(() => _status = _Status.taken);
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || _done) return;
    final problem = UsernameGatePolicy.localProblem(_name.text);
    if (problem != null) {
      setState(() => _status = _Status.bad);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _serverLine = null;
    });
    final res = await UsernameGateState.claim(_name.text);
    if (!mounted) {
      return;
    }
    if (res['success'] == true) {
      setState(() {
        _done = true;
        _busy = false;
      });
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    _failures++;
    setState(() {
      _busy = false;
      _status = _statusFromCode(res['code']);
      _serverLine = _lineFromCode(res['code'], res['error']);
    });
  }

  _Status _statusFromCode(Object? code) {
    switch (code?.toString()) {
      case 'taken':
        return _Status.taken;
      case 'reserved':
        return _Status.reserved;
      case 'format':
        return _Status.bad;
      case 'ratelimited':
        return _Status.rateLimited;
      default:
        return _Status.offline;
    }
  }

  String _lineFromCode(Object? code, Object? error) {
    switch (code?.toString()) {
      case 'taken':
        return 'That name is taken. Try another.';
      case 'reserved':
        return 'That name is reserved.';
      case 'ratelimited':
        return 'Too many tries. Wait a minute.';
      case 'format':
        return 'Letters, numbers and _ only, 3-20 characters.';
      default:
        return (error?.toString().isNotEmpty ?? false)
            ? error.toString()
            : "Couldn't save the name. Check your connection and try again.";
    }
  }

  Future<void> _adopt() async {
    final candidate = widget.previous;
    if (candidate == null || _busy) return;
    setState(() {
      _busy = true;
      _serverLine = null;
    });
    final ok = await UsernameGateState.adopt(candidate);
    if (!mounted) return;
    if (ok) {
      setState(() => _done = true);
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _mode = UsernameGateMode.claim;
      _serverLine =
          'That account needs its own sign-in. Pick a name for this phone.';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startFresh() {
    setState(() {
      _mode = UsernameGateMode.claim;
      _serverLine = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _later() {
    UsernameGateState.deferThisSession();
    Navigator.of(context).pop(false);
  }

  Future<void> _openRestore() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RestorePage()),
    );
    if (!mounted) return;
    final phase = await UsernameGateState.resolve();
    if (!mounted) return;
    if (phase == UsernameGate.notNeeded) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done,
      child: Scaffold(
        backgroundColor: AppThemeService.currentPalette.value
            .scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: PrismSpace.xl,
                vertical: PrismSpace.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _mode == UsernameGateMode.welcomeBack
                    ? _welcomeBack()
                    : _claim(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _claim() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge('@'),
        const SizedBox(height: PrismSpace.xl),
        Text(
          _done ? 'You are in.' : 'Pick your name',
          style: TextStyle(
            fontSize: PrismType.headline,
            fontWeight: PrismType.wBold,
            color: _ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: PrismSpace.xs),
        Text(
          _done
              ? 'Everything you watch, save and share now has a home.'
              : 'This is how friends find you and how your watching stays '
                  'yours. You can change it later, once a week.',
          style: TextStyle(fontSize: PrismType.body, color: _inkSoft, height: 1.45),
        ),
        const SizedBox(height: PrismSpace.xl),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PrismSpace.md,
            vertical: PrismSpace.xxs,
          ),
          decoration: BoxDecoration(
            color: _well,
            borderRadius: BorderRadius.circular(PrismRadius.md),
            border: Border.all(
              color: _status == _Status.bad || _status == _Status.taken
                  ? PrismAccent.danger.withValues(alpha: 0.6)
                  : (_isLight ? PrismLight.borderSubtle : Colors.white12),
            ),
          ),
          child: Row(
            children: [
              Text(
                '@',
                style: TextStyle(
                  fontSize: PrismType.section,
                  fontWeight: PrismType.wBold,
                  color: _inkFaint,
                ),
              ),
              const SizedBox(width: PrismSpace.xxs),
              Expanded(
                child: TextField(
                  controller: _name,
                  focusNode: _focus,
                  autofocus: true,
                  enabled: !_busy && !_done,
                  textInputAction: TextInputAction.done,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  maxLength: UsernameGatePolicy.maxLength,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    _LowercaseFormatter(),
                  ],
                  style: TextStyle(
                    fontSize: PrismType.section,
                    fontWeight: PrismType.wSemiBold,
                    color: _ink,
                  ),
                  cursorColor: _accent,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: PrismSpace.sm,
                    ),
                    hintText: 'your_name',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PrismSpace.xs),
        Text(
          _serverLine ?? _hint ?? '3-20 characters. Letters, numbers and _ only.',
          style: TextStyle(fontSize: PrismType.caption, color: _hintColor),
        ),
        const SizedBox(height: PrismSpace.lg),
        SizedBox(
          width: double.infinity,
          child: Align(
            child: PrismButton(
              label: _busy
                  ? 'Saving…'
                  : _done
                      ? 'Welcome'
                      : 'Claim @${_name.text.trim().isEmpty ? 'name' : UsernameGatePolicy.normalize(_name.text)}',
              icon: _done ? Icons.check_rounded : Icons.arrow_forward_rounded,
              accent: true,
              expanded: true,
              onPressed: _busy || _done ? null : _submit,
            ),
          ),
        ),
        const SizedBox(height: PrismSpace.xs),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _openRestore,
            child: Text(
              'New phone? Use a restore code',
              style: TextStyle(fontSize: PrismType.caption, color: _inkFaint),
            ),
          ),
        ),
        if (UsernameGatePolicy.canDefer(_failures) && !_done)
          Center(
            child: TextButton(
              onPressed: _busy ? null : _later,
              child: Text(
                'Later — I will set it next time',
                style: TextStyle(fontSize: PrismType.caption, color: _inkFaint),
              ),
            ),
          ),
      ],
    );
  }

  Widget _welcomeBack() {
    final p = widget.previous!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _badge(p.username.substring(0, 1).toUpperCase()),
        const SizedBox(height: PrismSpace.xl),
        Text(
          'Welcome back',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: PrismType.headline,
            fontWeight: PrismType.wBold,
            color: _ink,
          ),
        ),
        const SizedBox(height: PrismSpace.xxs),
        Text(
          '@${p.username}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: PrismType.section,
            fontWeight: PrismType.wBold,
            color: _accent,
          ),
        ),
        const SizedBox(height: PrismSpace.md),
        Text(
          'This phone was used with this account before. Continue with it '
          'and your name, friends and history come back.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: PrismType.body,
            color: _inkSoft,
            height: 1.45,
          ),
        ),
        const SizedBox(height: PrismSpace.xl),
        SizedBox(
          width: double.infinity,
          child: Center(
            child: PrismButton(
              label: _busy ? 'Bringing it back…' : 'Continue as @${p.username}',
              icon: Icons.restore_rounded,
              accent: true,
              expanded: true,
              onPressed: _busy ? null : _adopt,
            ),
          ),
        ),
        const SizedBox(height: PrismSpace.xs),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _startFresh,
            child: Text(
              'Not me — pick a new name',
              style: TextStyle(fontSize: PrismType.caption, color: _inkFaint),
            ),
          ),
        ),
        if (_serverLine != null)
          Padding(
            padding: const EdgeInsets.only(top: PrismSpace.xs),
            child: Text(
              _serverLine!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: PrismType.caption,
                color: PrismAccent.danger,
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(String glyph) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppThemeService.currentPalette.value.cardBackgroundColor,
          border: Border.all(
            color: _isLight ? PrismLight.borderSubtle : Colors.white12,
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.18),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 34,
            fontWeight: PrismType.wBold,
            color: _accent,
          ),
        ),
      ),
    );
  }
}

class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lower = newValue.text.toLowerCase();
    if (lower == newValue.text) return newValue;
    return newValue.copyWith(
      text: lower,
      selection: TextSelection.collapsed(offset: lower.length),
    );
  }
}

/// Boot/from-home entry point. Waits a short, bounded time for the server
/// read so a normal boot goes straight to the gate, then never blocks:
/// offline means "undecided", and an undecided gate shows nothing.
abstract final class UsernameGateFlow {
  static Future<void> maybeShow(BuildContext context) async {
    if (!UsernameGateState.possible) return;
    if (UsernameGateState.deferredThisSession) return;
    if (UsernameGateState.phase.value == UsernameGate.notNeeded) return;

    // Startup dialogs run before the cloud client finishes booting, so a
    // one-shot read here would silently skip the gate for the whole
    // session. Keep re-reading until the answer is real; each attempt is
    // single-flight and fails soft, so an offline boot just gives up.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (UsernameGateState.phase.value == UsernameGate.undecided &&
        DateTime.now().isBefore(deadline)) {
      await UsernameGateState.ensureResolved();
      if (UsernameGateState.phase.value != UsernameGate.undecided) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (UsernameGateState.phase.value != UsernameGate.needed) return;
    if (!context.mounted) return;

    final candidate = UsernameGateState.returning.value;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => UsernameGateScreen(
          mode: candidate != null
              ? UsernameGateMode.welcomeBack
              : UsernameGateMode.claim,
          previous: candidate,
        ),
      ),
    );
  }
}
