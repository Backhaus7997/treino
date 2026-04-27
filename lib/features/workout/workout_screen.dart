import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ENTRENAR',
            style: theme.textTheme.displayMedium?.copyWith(
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Rutinas y Workout Player',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
