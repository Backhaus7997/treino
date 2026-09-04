import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/presentation/legal/legal_content.dart';
import '../../auth/presentation/legal/legal_document_screen.dart';
import '../application/legacy_privacy_notice_providers.dart';

/// consentimiento-legal-versionado — R4.
///
/// Aviso NO bloqueante de política de privacidad actualizada, para el atleta
/// que aceptó antes de [kPrivacyV1PublishedAt].
///
/// Cumple la promesa que la sección 10 de la política ya hacía —"si los
/// cambios son relevantes, te lo avisaremos dentro de la app"— y que hasta
/// ahora no tenía ningún camino que la respaldara.
///
/// **Deliberadamente no bloquea nada.** Se monta en el `Stack` de Home junto
/// a `PermissionGate` / `OnboardingGate` / `TrainerLocationConsentGate`, y
/// cuando no corresponde colapsa a `SizedBox.shrink()`: cero impacto de
/// layout, igual que sus vecinos. Al atleta el texto viejo le era
/// sustancialmente cierto, así que interrumpirle el uso de la app para
/// contarle una precisión sería desproporcionado.
class LegacyPrivacyNoticeBanner extends ConsumerWidget {
  const LegacyPrivacyNoticeBanner({super.key});

  void _openPrivacy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LegalDocumentScreen(
          title: 'Política de Privacidad',
          sections: kPrivacySections,
          lastUpdated: kPrivacyLastUpdated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shouldShowLegacyPrivacyNoticeProvider)) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Material(
            key: const Key('legacy_privacy_notice_banner'),
            color: palette.bgElevated,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(TreinoIcon.infoCircle, color: palette.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      // `.min` no es cosmético: con el default `.max` este
                      // Column estira el Row, y con él la tarjeta entera, a
                      // los 600px del alto disponible. El aviso "no
                      // bloqueante" terminaba tapando la app completa y
                      // comiéndose todos los taps. Lo agarró el test de
                      // no-bloqueo, no la vista.
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.legacyPrivacyNoticeTitle,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.legacyPrivacyNoticeBody,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          key: const Key('legacy_privacy_notice_read'),
                          onTap: () => _openPrivacy(context),
                          child: Text(
                            l10n.legacyPrivacyNoticeAction,
                            style: TextStyle(
                              color: palette.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('legacy_privacy_notice_dismiss'),
                    tooltip: l10n.legacyPrivacyNoticeDismiss,
                    onPressed: () => ref
                        .read(legacyPrivacyNoticeDismissedProvider.notifier)
                        .markDismissed(),
                    icon: Icon(TreinoIcon.close, color: palette.textMuted),
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
