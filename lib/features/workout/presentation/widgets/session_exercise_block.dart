// Shared read-only exercise block: exercise name heading + one row per set.
// Used by both the athlete's SessionDetailScreen and the trainer's
// coach-hub expansion. No provider reads, no edit/delete affordances
// (REQ-SETLOGS-006, REQ-SETLOGS-009).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/set_log.dart';

/// Displays one exercise group: name heading followed by a row per [SetLog].
/// API matches the old private `_ExerciseBlock` in session_detail_screen.dart.
class SessionExerciseBlock extends StatelessWidget {
  const SessionExerciseBlock({
    super.key,
    required this.exerciseName,
    required this.sets,
  });

  final String exerciseName;
  final List<SetLog> sets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exerciseName,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: palette.textPrimary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ...sets.map((log) => _SetRow(log: log)),
        ],
      ),
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  const _SetRow({required this.log});

  final SetLog log;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${log.setNumber}',
              style: TextStyle(color: palette.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${log.reps} reps',
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
          Text(
            '${log.weightKg} kg',
            style: TextStyle(color: palette.textPrimary),
          ),
          const SizedBox(width: 8),
          const _PrBadgeStub(),
        ],
      ),
    );
  }
}

// ── PR badge stub ─────────────────────────────────────────────────────────────
// Placeholder widget — no params, no logic. Grep-friendly name for Etapa 5.

class _PrBadgeStub extends StatelessWidget {
  const _PrBadgeStub();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        AppL10n.of(context).workoutDetailPrBadge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: palette.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
