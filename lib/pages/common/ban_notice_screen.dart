import 'package:flutter/material.dart';

import 'package:dizzy/design/dizzy_tactile.dart';
import 'package:dizzy/design/dizzy_tokens.dart';
import 'package:dizzy/services/moderation/ban_service.dart';
import 'package:dizzy/widgets/common/notify.dart';
import 'package:dizzy/widgets/tactile/dizzy_tactile_button.dart';

/// D3 — full-ban notice (Easy English, appeal path, never a dead end).
/// social-level bans never reach here; they only gate social entries.
class BanNoticeScreen extends StatefulWidget {
  const BanNoticeScreen({super.key});

  @override
  State<BanNoticeScreen> createState() => _BanNoticeScreenState();
}

class _BanNoticeScreenState extends State<BanNoticeScreen> {
  late final TextEditingController _appeal;

  @override
  void initState() {
    super.initState();
    _appeal = TextEditingController(text: '');
    BanService.loadAppealDraft().then((d) {
      if (d.isNotEmpty && mounted) _appeal.text = d;
    });
  }

  @override
  void dispose() {
    _appeal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tooShort = _appeal.text.trim().length < 10;
    final ok = await BanService.submitAppeal(_appeal.text);
    if (!ok) await BanService.saveAppealDraft(_appeal.text);
    if (!mounted) return;
    if (ok) {
      DizzyNotify.show(context, 'Appeal sent. We will look at it soon.',
          tone: NotifyTone.success);
      Navigator.of(context).pop();
    } else {
      DizzyNotify.show(
          context,
          tooShort
              ? 'A little more detail helps (10+ characters).'
              : 'Could not send yet — your text is saved, try again.',
          tone: NotifyTone.warn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DizzyVoid.voidA,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DizzySpace.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DizzyGlow.red.withValues(alpha: 0.12),
                      border: Border.all(color: DizzyGlow.red, width: 2),
                    ),
                    child: const Icon(Icons.block_rounded,
                        color: DizzyGlow.red, size: 40),
                  ),
                  const SizedBox(height: DizzySpace.lg),
                  const Text(
                    'Account paused',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: DizzyVoid.bone,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  ValueListenableBuilder<BanState>(
                    valueListenable: BanService.state,
                    builder: (context, ban, _) => Text(
                      ban.easyEnglish.isEmpty
                          ? 'This account is suspended.'
                          : ban.easyEnglish,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: DizzyVoid.ash, fontSize: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: DizzySpace.md),
                  const Text(
                    'Think this is a mistake? Tell us what happened — we will\n'
                    'review it. Nothing you type is lost if sending fails.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: DizzyVoid.ash, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: DizzySpace.lg),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: DizzyVoid.voidA,
                      borderRadius: BorderRadius.circular(DizzyRadius.lg),
                      border: Border.all(
                          color: DizzyVoid.bone.withValues(alpha: 0.12)),
                    ),
                    padding: const EdgeInsets.all(DizzySpace.md),
                    child: TextField(
                      controller: _appeal,
                      maxLines: 5,
                      maxLength: 1000,
                      onChanged: BanService.saveAppealDraft,
                      style: const TextStyle(
                          color: DizzyVoid.bone, fontSize: 14, height: 1.5),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'What happened? (10+ characters)',
                        hintStyle:
                            TextStyle(color: DizzyVoid.ash, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: DizzySpace.lg),
                  DizzyTactileButton(
                    width: double.infinity,
                    height: 48,
                    gradient: DizzyGradients.beamButton,
                    onTap: _submit,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Send appeal',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DizzySpace.sm),
                  DizzyTactileButton(
                    width: double.infinity,
                    height: 44,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                          color: DizzyVoid.ash,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
