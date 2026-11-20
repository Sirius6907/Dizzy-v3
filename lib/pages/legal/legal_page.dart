import 'package:flutter/material.dart';

import '../../design/prism_tokens.dart';
import '../../services/legal/legal_acceptance_service.dart';
import '../../services/legal/legal_terms.dart';
import '../../services/theme/app_theme_service.dart';
import '../../widgets/common/offline_aware_scaffold.dart';

/// The text behind the agree checkbox: Terms & Privacy in one scrollable page.
///
/// Reached from the onboarding sheet ("read it") and from Settings → Privacy.
/// When the install has not agreed to [LegalTerms.version] the page carries the
/// agree action itself, so a version bump can be resolved here instead of
/// forcing the whole consent sheet open again.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isLight = palette.isLight;
    final ink = isLight ? PrismLight.ink : Colors.white;
    final inkSoft = isLight ? PrismLight.inkSoft : Colors.white60;
    final border = isLight
        ? PrismLight.borderSubtle
        : Colors.white.withValues(alpha: 0.08);

    return OfflineAwareScaffold(
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
          'Terms & Privacy',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ValueListenableBuilder<String?>(
            valueListenable: LegalAcceptanceService.acceptedVersion,
            builder: (context, accepted, _) {
              final pending = accepted != LegalTerms.version;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Version ${LegalTerms.version}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: PrismAccent.text(isLight),
                          ),
                        ),
                      ),
                      if (!pending)
                        ValueListenableBuilder<DateTime?>(
                          valueListenable: LegalAcceptanceService.acceptedAt,
                          builder: (context, at, _) => Text(
                            'Agreed ${LegalAcceptanceService.describeAcceptedAt(at)}',
                            style: TextStyle(fontSize: 12, color: inkSoft),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final s in LegalTerms.sections) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: palette.cardBackgroundColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.headline,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.body,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (pending) ...[
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: () async {
                        await LegalAcceptanceService.accept();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('I agree'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You can keep every data switch off and still agree — the '
                      'agreement covers using the app, not collecting data.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: inkSoft),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
