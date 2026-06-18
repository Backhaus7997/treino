import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/domain/muscle_group.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/routine_day_duration.dart';
import '../application/todays_routine_provider.dart';
import 'home_cta_button.dart';

/// "Empezar Entrenamiento" card.
///
/// Reads [todaysRoutineProvider] for the resolved routine + day + week.
/// While the provider is loading or errored the card renders a stable
/// skeleton with the static "EMPEZAR ENTRENAMIENTO" CTA disabled so the
/// home doesn't flicker on cold start.
///
/// Tap on the CTA pushes `/workout/routine/{routineId}?day=N&week=M` so the
/// athlete lands directly on today's day pre-selected — saving the extra
/// tap on the day selector. Decision log 2026-06-18.
class EmpezarEntrenamientoCard extends ConsumerWidget {
  const EmpezarEntrenamientoCard({super.key});

  static const _ctaLabel = 'EMPEZAR ENTRENAMIENTO';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final todayAsync = ref.watch(todaysRoutineProvider);

    // The weekday prefix is always shown — it's derived from the device
    // clock, not the provider. Keeps the card layout stable while the
    // provider resolves.
    final dayPrefix =
        '${l10n.dashboardDateToday.toUpperCase()} · ${_weekdayName(l10n, DateTime.now().weekday)}';

    // Resolve display strings + tap target from the provider. Loading and
    // error states fall back to "—" placeholders + a disabled CTA so the
    // home doesn't navigate to a stale destination during the gap.
    final today = todayAsync.valueOrNull;
    final heroLabel = today?.day.name.toUpperCase() ?? '—';
    final subtitle = today != null ? _muscleSubtitle(today.day) : '';
    final exerciseCount = today != null
        ? '${today.day.slots.length} ${today.day.slots.length == 1 ? "ejercicio" : "ejercicios"}'
        : '— ejercicios';
    final duration = today != null
        ? _formatDuration(today.day, today.weekNumber)
        : '—';
    final canStart = today != null;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day label
            Text(
              dayPrefix,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.4,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 8),
            // Hero day name (e.g. "DÍA 4" or "PUSH" if the routine authored
            // a custom name on the day).
            Text(
              heroLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 36,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // Muscle groups subtitle (deduped, ordered as they appear in
            // the day's slots).
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
            const SizedBox(height: 14),
            // Stat row
            Row(
              children: [
                Icon(TreinoIcon.tabWorkout, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  exerciseCount,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Icon(TreinoIcon.clock, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            HomeCTAButton(
              label: _ctaLabel,
              leadingIcon: TreinoIcon.play,
              // While the provider is loading/null the CTA is gated to the
              // workout tab as a safe fallback — tapping never dead-ends.
              onPressed: canStart
                  ? () => context.push(
                        '/workout/routine/${today.routine.id}'
                        '?day=${today.dayNumber}'
                        '&week=${today.weekNumber}',
                      )
                  : () => context.go('/workout'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deduped Spanish muscle-group labels joined with " · ", preserving the
/// slots' source order. Empty days resolve to "" (the caller hides the
/// row when empty).
String _muscleSubtitle(RoutineDay day) {
  final seen = <String>{};
  final labels = <String>[];
  for (final slot in day.slots) {
    final label = muscleGroupLabel(slot.muscleGroup);
    if (seen.add(label)) labels.add(label);
  }
  return labels.join(' · ');
}

/// Authored estimate when present, otherwise the rule-of-thumb computed by
/// [estimateRoutineDayMinutes] for [week]. Authored values render without
/// the "~" prefix; computed values include it to read as approximate.
/// Returns "—" when nothing measurable is on the day (e.g. all-empty slots).
String _formatDuration(RoutineDay day, int week) {
  final est = estimateRoutineDayMinutes(day, week: week);
  if (est.minutes == null) return '—';
  return est.authored ? '${est.minutes} min' : '~${est.minutes} min';
}

String _weekdayName(AppL10n l10n, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return l10n.dashboardWeekday1;
    case DateTime.tuesday:
      return l10n.dashboardWeekday2;
    case DateTime.wednesday:
      return l10n.dashboardWeekday3;
    case DateTime.thursday:
      return l10n.dashboardWeekday4;
    case DateTime.friday:
      return l10n.dashboardWeekday5;
    case DateTime.saturday:
      return l10n.dashboardWeekday6;
    default:
      return l10n.dashboardWeekday7;
  }
}
