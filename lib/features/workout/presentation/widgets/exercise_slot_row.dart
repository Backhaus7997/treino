import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/reps_format.dart';
import '../../domain/routine_slot.dart';

/// Tappeable row that displays one [RoutineSlot] inside [RoutineDetailScreen].
/// Receives all data by constructor — no ref.watch / ref.read.
class ExerciseSlotRow extends StatelessWidget {
  const ExerciseSlotRow({
    super.key,
    required this.slot,
    required this.index,
    required this.onTap,
    this.lastWeightDisplay,
    this.week = 0,
  });

  final RoutineSlot slot;

  /// 1-based ordinal of this slot inside the day. Shown in the leading box.
  final int index;

  final VoidCallback onTap;

  /// null → renders dash inside the ÚLTIMO badge (Fase 2 state).
  final String? lastWeightDisplay;

  /// 0-based week index for week-aware prescription display (REQ-PERIOD-041).
  /// Default 0 keeps single-week callers unchanged (backward-compat).
  final int week;

  /// Builds the sets·reps/duration summary string for the given [week].
  ///
  /// Uses [slot.effectiveSetsForWeek(week)] when [slot.weeklySets] is
  /// populated; falls back to legacy scalar fields for single-week slots.
  ///
  /// Priority for week-aware path:
  ///  1. Duration-based spec (durationSeconds > 0) → "<count> · MM:SS"
  ///  2. Reps spec → "<count> · <formatted reps>"
  ///  3. Range spec (repsMin / repsMax) → "<count> · <min>–<max>"
  ///
  /// Fallback (weeklySets empty):
  ///  1. durationSeconds > 0 → "<targetSets> · MM:SS"
  ///  2. targetReps non-empty → "<targetSets> · <formatted reps>"
  ///  3. Legacy → "<targetSets> · <min>–<max>"
  static String _setsRepsSummary(RoutineSlot slot, int week) {
    // Week-aware path: resolve from weeklySets when available.
    if (slot.weeklySets.isNotEmpty) {
      final specs = slot.effectiveSetsForWeek(week);
      final count = specs.length;
      if (specs.isNotEmpty) {
        final first = specs.first;
        if (first.durationSeconds != null && first.durationSeconds! > 0) {
          final total = first.durationSeconds!;
          final mm = (total ~/ 60).toString().padLeft(2, '0');
          final ss = (total % 60).toString().padLeft(2, '0');
          return '$count · $mm:$ss';
        }
        if (first.reps != null) {
          // Homogeneous per-set reps list.
          final allSame = specs.every((s) => s.reps == first.reps);
          if (allSame) return '$count · ${first.reps}';
          return '$count · ${formatReps(specs.map((s) => s.reps ?? 0).toList())}';
        }
        if (first.repsMin != null && first.repsMax != null) {
          return '$count · ${first.repsMin}–${first.repsMax}';
        }
      }
      return '$count sets';
    }

    // Legacy fallback (weeklySets empty — single-week slot).
    if (slot.durationSeconds != null && slot.durationSeconds! > 0) {
      final total = slot.durationSeconds!;
      final mm = (total ~/ 60).toString().padLeft(2, '0');
      final ss = (total % 60).toString().padLeft(2, '0');
      return '${slot.targetSets} · $mm:$ss';
    }
    if (slot.targetReps.isNotEmpty) {
      return '${slot.targetSets} · ${formatReps(slot.targetReps)}';
    }
    // Legacy fallback: min–max reps from old docs.
    return '${slot.targetSets} · ${slot.targetRepsMin}–${slot.targetRepsMax}';
  }

  /// Formats rest seconds: "1:30" when >= 60, "45s" when < 60.
  static String _restDisplay(int restSeconds) {
    if (restSeconds <= 0) return '0s';
    if (restSeconds >= 60) {
      final mm = (restSeconds ~/ 60).toString().padLeft(2, '0');
      final ss = (restSeconds % 60).toString().padLeft(2, '0');
      return '$mm:$ss';
    }
    return '${restSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final setsReps = _setsRepsSummary(slot, week);
    final restText = _restDisplay(slot.restSeconds);
    return Semantics(
      button: true,
      label: 'Ejercicio ${slot.exerciseName}, $setsReps, descanso $restText',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: palette.bgCard,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ordinal — replaces the placeholder dumbbell icon. Same
                // 48x48 box; the number tells the athlete the exercise order
                // within the day.
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.bgCard,
                    border: Border.all(color: palette.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$index',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.exerciseName.toUpperCase(),
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 0.5,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            setsReps,
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w400,
                              fontSize: 13,
                              color: palette.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '·',
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              color: palette.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            slot.muscleGroup.toUpperCase(),
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            TreinoIcon.timer,
                            size: 14,
                            color: palette.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$restText descanso',
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w400,
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _UltimoBadge(value: lastWeightDisplay),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UltimoBadge extends StatelessWidget {
  const _UltimoBadge({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ÚLTIMO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          Text(
            value ?? '—',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
