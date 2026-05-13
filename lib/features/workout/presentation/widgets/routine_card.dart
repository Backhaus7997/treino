import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../profile/domain/experience_level.dart';
import '../../domain/routine.dart';

class RoutineCard extends StatelessWidget {
  const RoutineCard({required this.routine, super.key});

  final Routine routine;

  /// Total exercises across all days. Computed inline (no [Routine.totalExercises]
  /// getter — domain model is unchanged per ADR-D5).
  int get _totalExercises =>
      routine.days.fold(0, (sum, day) => sum + day.slots.length);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => context.push('/workout/routine/${routine.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon square (40×40, radius 12, accent icon on espresso fill).
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.espresso,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                TreinoIcon.tabWorkout,
                color: palette.accent,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              routine.name.toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${routine.level.displayNameEs} · $_totalExercises ej.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
