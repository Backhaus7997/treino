import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/routine_slot.dart';

/// Tappeable row that displays one [RoutineSlot] inside [RoutineDetailScreen].
/// Receives all data by constructor — no ref.watch / ref.read.
class ExerciseSlotRow extends StatelessWidget {
  const ExerciseSlotRow({
    super.key,
    required this.slot,
    required this.onTap,
    this.lastWeightDisplay,
  });

  final RoutineSlot slot;
  final VoidCallback onTap;

  /// null → renders dash inside the ÚLTIMO badge (Fase 2 state).
  final String? lastWeightDisplay;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label:
          'Ejercicio ${slot.exerciseName}, ${slot.targetSets} series de ${slot.targetRepsMin} a ${slot.targetRepsMax} repeticiones, descanso ${slot.restSeconds} segundos',
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
                // Thumb
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.bgCard,
                    border: Border.all(color: palette.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    TreinoIcon.tabWorkout,
                    size: 24,
                    color: palette.textMuted,
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
                            '${slot.targetSets} · ${slot.targetRepsMin}–${slot.targetRepsMax}',
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
                            '${slot.restSeconds}s descanso',
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
