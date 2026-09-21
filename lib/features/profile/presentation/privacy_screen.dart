import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../core/analytics/analytics_consent.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';

/// Los controles de privacidad del usuario. Hoy, uno solo: la analítica.
///
/// Existe porque la Política de Privacidad promete que el consentimiento se
/// puede **revocar en cualquier momento** y la app no tenía dónde. Un documento
/// que el usuario acepta no puede prometer un control que no existe — es la
/// misma clase de afirmación falsa que persigue la §11.1 de AGENTS.md, sólo que
/// publicada.
///
/// El interruptor aplica en el acto (ver [AnalyticsConsentNotifier]), no al
/// próximo arranque: «en cualquier momento» quiere decir ahora.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final habilitada = ref.watch(analyticsConsentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header — mismo patrón que las hermanas de perfil ────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => context.pop(),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  l10n.privacyTitle.toUpperCase(),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── El interruptor ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TreinoFadeSlideIn(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: palette.textMuted.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      TreinoIcon.shieldCheck,
                      size: 20,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.privacyAnalyticsTitle,
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.privacyAnalyticsSubtitle,
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      label: l10n.privacyAnalyticsTitle,
                      toggled: habilitada,
                      child: Switch(
                        value: habilitada,
                        activeThumbColor: palette.accent,
                        onChanged: (v) => ref
                            .read(analyticsConsentProvider.notifier)
                            .setEnabled(v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Qué implica, dicho sin eufemismos ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            l10n.privacyAnalyticsExplainer,
            style: GoogleFonts.barlow(
              fontSize: 13,
              height: 1.45,
              color: palette.textMuted,
            ),
          ),
        ),

        // La aclaración de Crashlytics va SIEMPRE visible, no detrás de un
        // "ver más". Un interruptor rotulado «analítica» que deja otra
        // recolección prendida y no lo dice es una media verdad, y una media
        // verdad en una pantalla de privacidad es peor que no tener la pantalla.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            l10n.privacyAnalyticsCrashNote,
            style: GoogleFonts.barlow(
              fontSize: 12,
              height: 1.45,
              color: palette.textMuted.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}
