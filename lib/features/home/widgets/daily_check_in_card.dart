import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../checkins/application/check_in_providers.dart';
import '../../checkins/domain/check_in.dart';
import '../../checkins/presentation/wellbeing_check_in_sheet.dart';
import '../../checkins/presentation/widgets/wellbeing_mood_row.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;

/// Check-in diario de bienestar, en Inicio.
///
/// **Por qué acá y no en Perfil.** Marta —el perfil que originó el hallazgo de
/// #643— mide su progreso por cuánto le duele al levantarse, y entrena dos
/// veces por semana: un registro atado sólo a la sesión la deja cinco días sin
/// dato. Inicio es donde el atleta ya mira su estado del día; Perfil, además,
/// choca de frente con #642.
///
/// **Registrar cuesta dos toques**: el emoji abre el sheet ya precargado con
/// el nivel elegido, así el tap de la tarjeta no se pierde. El resto del
/// formulario (dolor, zona, nota) es opcional y vive en el sheet.
///
/// ⚠️ La tarjeta REGISTRA y muestra lo registrado. No interpreta, no compara
/// con ayer, no felicita ni alerta. No hay puntaje, racha ni recompensa por
/// registrar: eso sería gamificación, fuera de alcance por AGENTS.md regla 4.
class DailyCheckInCard extends ConsumerWidget {
  const DailyCheckInCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    // Fecha LOCAL: el que se levanta a las 6 en Córdoba espera que su registro
    // cuente para HOY, no para el día de UTC.
    final today = checkInDateKey(DateTime.now());

    // Best-effort, igual que el resto de Inicio: mientras carga o si falla, se
    // ofrece el registro normal. Un spinner o un error acá taparían la tarjeta
    // por un dato que es opcional de por sí.
    final dayCheckIns = uid.isEmpty
        ? const <CheckIn>[]
        : ref
                .watch(checkInsForDateProvider((uid: uid, date: today)))
                .valueOrNull ??
            const <CheckIn>[];
    // El último del día, venga del entreno o de esta misma tarjeta: para el
    // usuario "hoy" es uno solo. Editar reescribe ESE documento.
    final existing = latestCheckIn(dayCheckIns);

    Future<void> open(CheckInFeeling? feeling) => showWellbeingCheckInSheet(
          context,
          initialFeeling: feeling,
          existing: existing,
        );

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.wellbeingDailyTitle,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (existing == null) ...[
              Text(
                l10n.wellbeingDailyPrompt,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              WellbeingMoodScale(onSelect: open),
            ] else
              WellbeingCheckInRecorded(
                checkIn: existing,
                onEdit: () => open(existing.feeling),
              ),
          ],
        ),
      ),
    );
  }
}
