import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'COACH',
            style: theme.textTheme.displayMedium?.copyWith(
              color: palette.highlight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Personal Trainers cerca tuyo',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
