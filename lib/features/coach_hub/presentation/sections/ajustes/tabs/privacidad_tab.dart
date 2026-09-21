import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/analytics/analytics_consent.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';

/// El interruptor de analítica, del lado web.
///
/// Espejo de `PrivacyScreen` en mobile, y espejo a propósito: la Política de
/// Privacidad es una sola y promete lo mismo a las dos superficies. Tener el
/// control en una y no en la otra dejaría al documento diciendo algo que sólo
/// es cierto en la mitad del producto.
///
/// La preferencia es POR DISPOSITIVO (vive en `SharedPreferences`, como el
/// tema), así que apagarla acá no la apaga en el teléfono. Eso está dicho en
/// pantalla, no dejado a que el usuario lo deduzca.
class PrivacidadTab extends ConsumerWidget {
  const PrivacidadTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    // Mismo guard que `AparienciaTab`: en web el provider de preferencias
    // puede no estar resuelto todavía, y `.requireValue` tiraría.
    final habilitada = ref.watch(sharedPreferencesProvider).maybeWhen(
          data: (_) => ref.watch(analyticsConsentProvider),
          orElse: () => true,
        );
    final listo = ref
        .watch(sharedPreferencesProvider)
        .maybeWhen(data: (_) => true, orElse: () => false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIVACIDAD',
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w700,
            letterSpacing: AppFonts.headingTracking,
            color: palette.textPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          'Qué registramos sobre cómo usás TREINO, y cómo apagarlo.',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: palette.textMuted.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s18,
              vertical: AppSpacing.s12,
            ),
            child: Row(
              children: [
                Icon(
                  TreinoIcon.shieldCheck,
                  size: AppSpacing.s20,
                  color: palette.textMuted,
                ),
                const SizedBox(width: AppSpacing.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analítica de uso',
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontWeight: AppFonts.w600,
                          color: palette.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        'Nos ayuda a entender qué partes del Coach Hub se usan.',
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Semantics(
                  label: 'Analítica de uso',
                  toggled: habilitada,
                  child: Switch(
                    value: habilitada,
                    activeThumbColor: palette.accent,
                    onChanged: listo
                        ? (v) => ref
                            .read(analyticsConsentProvider.notifier)
                            .setEnabled(v)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        Text(
          'Si la desactivás, TREINO deja de registrar cómo usás el Coach Hub. '
          'No afecta tus alumnos, tus rutinas ni tus cobros. Podés volver a '
          'activarla cuando quieras.',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        // Las dos aclaraciones incómodas van visibles, no escondidas: un
        // interruptor rotulado «analítica» que deja otra recolección prendida,
        // o que el usuario cree global y es por dispositivo, es la clase de
        // media verdad que la §11.1 de AGENTS.md persigue.
        Text(
          'Es una preferencia de ESTE navegador: si también usás la app en el '
          'teléfono, ahí se configura aparte. Y no incluye los reportes de '
          'errores, que seguimos recibiendo para arreglar fallas y no '
          'describen lo que hacés.',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted.withValues(alpha: 0.75),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
