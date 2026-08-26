import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/primitives.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/template_preferences_providers.dart';
import '../onboarding/templates_onboarding_gate.dart';
import '../onboarding/templates_onboarding_steps.dart';

/// Barra de PLANTILLAS que muestra por qué la grilla está en ese orden, y deja
/// ajustarlo (#635 PR#3).
///
/// ## Resumen + entrada, no un segundo selector
///
/// El issue pide "filtros editables". La tentación era construir cuatro
/// controles nuevos acá; en cambio esto MUESTRA lo respondido y delega el
/// editar al mismo flow de 4 pasos de #660, sembrado con las respuestas
/// actuales.
///
/// Dos razones. Una: dos UIs para la misma pregunta divergen — la del
/// onboarding explica cada dimensión con una bajada, y una barra compacta no
/// tiene lugar para eso, así que terminarían preguntando lo mismo con
/// distintas palabras. Dos: es la mitad del código, y el ranking ya vive en un
/// provider derivado que no le importa quién escribió las preferencias.
///
/// ## Dice ORDENADO, no filtrado
///
/// Con 7 plantillas en el catálogo un filtro duro vacía la grilla en la
/// mayoría de las combinaciones (ver `TemplateAffinity`). La copy no puede
/// prometer que esconde lo que no encaja, porque no lo hace: nada desaparece,
/// sólo cambia el orden.
class TemplatesPreferencesBar extends ConsumerWidget {
  const TemplatesPreferencesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final prefs = ref.watch(athleteTemplatePreferencesProvider);
    final answered = !prefs.isEmpty;

    final resumen = <String>[
      if (prefs.daysPerWeek != null)
        l10n.routineCardDaysPerWeek(prefs.daysPerWeek!),
      if (prefs.minutesPerSession != null)
        l10n.routineCardMinutes('${prefs.minutesPerSession}'),
      if (prefs.goal != null) templatesGoalLabel(l10n, prefs.goal!),
      for (final g in prefs.priorityGroups) templatesZoneLabel(l10n, g),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // Sin respuestas no hay orden que explicar: la fila entera
                  // pasa a ser una invitación en vez de un resumen vacío.
                  answered ? l10n.templatesFilterBarHint : '',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    height: 1.2,
                    color: palette.textMuted,
                  ),
                ),
                if (answered) ...[
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    // Separador de punto medio, no coma: son etiquetas
                    // yuxtapuestas, no una enumeración gramatical.
                    resumen.join(' · '),
                    key: const Key('templates_preferences_summary'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.3,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          TextButton.icon(
            key: const Key('templates_preferences_adjust'),
            onPressed: () =>
                showTemplatesPreferencesEditor(context: context, ref: ref),
            icon: Icon(TreinoIcon.edit, size: 16, color: palette.accent),
            label: Text(
              answered
                  ? l10n.templatesFilterBarAdjust
                  : l10n.templatesFilterBarSetUp,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
                color: palette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
