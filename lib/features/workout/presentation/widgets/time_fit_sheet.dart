import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/routine_day.dart';
import '../../domain/session_time_fit.dart';

/// Las franjas que ofrece la hoja. Fijas y redondas a propósito: la pregunta
/// es "cuánto tengo hoy", no "cuántos minutos exactos" — un input libre pide
/// una precisión que el atleta no tiene y que la estimación tampoco.
const List<int> kTimeFitChoices = [20, 30, 45, 60, 75, 90];

/// La hoja donde el atleta declara cuánto tiempo tiene y ve qué propone la app
/// sacar para que la sesión entre (#645).
///
/// **La app sugiere, no recorta sola.** Elegir una franja no cambia nada: sólo
/// muestra la propuesta. El recorte se aplica cuando el atleta toca AJUSTAR
/// HOY, y hasta ahí puede cerrar la hoja sin consecuencias. Un recorte
/// automático —sin mostrar el criterio ni pedir permiso— es exactamente lo que
/// hace que un plan se lea como "capaz hace cualquier cosa".
///
/// Nunca escribe la rutina: `onApply` termina en `dropExercisesForToday`, que
/// es local a la sesión de hoy.
class TimeFitSheet extends StatefulWidget {
  const TimeFitSheet({
    super.key,
    required this.day,
    required this.week,
    required this.lockedExerciseIds,
    required this.onApply,
  });

  final RoutineDay day;
  final int week;
  final Set<String> lockedExerciseIds;
  final void Function(List<String> exerciseIds) onApply;

  @override
  State<TimeFitSheet> createState() => _TimeFitSheetState();
}

class _TimeFitSheetState extends State<TimeFitSheet> {
  int? _selected;

  SessionTimeFitPlan? get _plan {
    final minutes = _selected;
    if (minutes == null) return null;
    return planSessionTimeFit(
      day: widget.day,
      availableMinutes: minutes,
      week: widget.week,
      lockedExerciseIds: widget.lockedExerciseIds,
    );
  }

  String _namesOf(List<String> ids) => widget.day.slots
      .where((s) => ids.contains(s.exerciseId))
      .map((s) => s.exerciseName)
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final plan = _plan;
    final drops = plan?.dropExerciseIds ?? const <String>[];
    final current = estimateSessionMinutes(widget.day, week: widget.week);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.sessionTimeFitPromptTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          if (current != null) ...[
            const SizedBox(height: AppSpacing.hairline),
            Text(
              l10n.sessionTimeFitCurrent('~$current'),
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final choice in kTimeFitChoices)
                _TimeFitChoiceChip(
                  minutes: choice,
                  selected: choice == _selected,
                  onTap: () => setState(() => _selected = choice),
                ),
            ],
          ),
          if (plan != null) ...[
            const SizedBox(height: 18),
            Text(
              switch (plan.outcome) {
                SessionTimeFitOutcome.alreadyFits =>
                  l10n.sessionTimeFitAlreadyFits('$_selected'),
                SessionTimeFitOutcome.trimSuggested =>
                  l10n.sessionTimeFitTrimHeadline('~${plan.projectedMinutes}'),
                SessionTimeFitOutcome.cannotFit when drops.isNotEmpty =>
                  l10n.sessionTimeFitCannotFit('~${plan.projectedMinutes}'),
                _ => l10n.sessionTimeFitNothingToTrim,
              },
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textPrimary,
              ),
            ),
            if (drops.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                _namesOf(drops),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.5,
                  color: palette.highlight,
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.commonCancel,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    disabledBackgroundColor: palette.border,
                  ),
                  onPressed: drops.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onApply(drops);
                        },
                  child: Text(
                    l10n.sessionTimeFitApply,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: TreinoButtonTokens.foreground(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una franja de tiempo de la hoja.
class _TimeFitChoiceChip extends StatelessWidget {
  const _TimeFitChoiceChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          border: Border.all(color: selected ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          l10n.routineCardMinutes('$minutes'),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.5,
            // Sobre el acento va el ink invariante, nunca palette.bg: en el
            // tema claro ese par da 1.57:1 (AGENTS.md §2).
            color: selected
                ? TreinoButtonTokens.foreground(context)
                : palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
